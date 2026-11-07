package snax_acc.qcgemm

// QC-GeMMX array (qcacc/ARCH.md "Datapath"): the dense GemmArray / Mesh / Tile of snax_acc.gemm with
// the 8 multipliers per tile replaced by
//   * a per-row 2-point butterfly (QcRowButterfly): x_k = a_k - subtraction_a (9 b),
//     s_p = x_2p + x_2p+1, d_p = x_2p - x_2p+1 (10 b), shared by all columns of the row,
//   * a per-column decoder (QcColumnDecoder) of the 64-bit B code word (16 blocks x 4 b),
//     shared by all rows of the column,
//   * per tile a 4-term select-sum (QcTile): sum_p +-{0, x_2p, x_2p+1, s_p, d_p}.
// Accumulator, add-C, valid/ready control of QcTile are the dense Tile's, line for line.

import chisel3._
import chisel3.util._

import snax_acc.gemm._

object QcGemm {
  // B code word: (meshCol / 2) x (tileSize / 2) blocks x 4 b = meshCol * tileSize bits (8x8: 64 b)
  def codeWidth(p: GemmParams): Int = p.meshCol * p.tileSize
  def pairs(p: GemmParams): Int = p.tileSize / 2
  def xWidth(p: GemmParams): Int = p.dataWidthA + 1 // a - subtraction_a
  def sWidth(p: GemmParams): Int = p.dataWidthA + 2 // butterfly outputs (and x, sign-extended)
  def check(p: GemmParams): Unit = {
    require(p.meshCol % 2 == 0, "QC: meshCol must be even (2x2 blocks)")
    require(p.tileSize % 2 == 0, "QC: tileSize must be even (2x2 blocks)")
  }
  // select indices into the per-row candidate vector
  val X_EVEN = 0
  val X_ODD = 1
  val SUM = 2
  val DIFF = 3
}

// decoded select of one (column n, pair p): value = en ? (neg ? -cand(sel) : cand(sel)) : 0
class QcSel extends Bundle {
  val en = Bool()
  val neg = Bool()
  val sel = UInt(2.W)
}

// Per column: block (j = n/2, p), nibble j*P + p, bits [1:0] = a, [3:2] = b; trit 00 = 0, 01 = +1,
// 11 = -1 (10: treated as 0).  Even n -> coefficients (a, b) on (x_2p, x_2p+1), odd n -> (b, a).
class QcColumnDecoder(params: GemmParams) extends Module with RequireAsyncReset {
  val P = QcGemm.pairs(params)
  val io = IO(new Bundle {
    val code_i = Input(UInt(QcGemm.codeWidth(params).W))
    val sel_o = Output(Vec(params.meshCol, Vec(P, new QcSel)))
  })
  for (n <- 0 until params.meshCol; p <- 0 until P) {
    val blk = (n / 2) * P + p
    val nib = io.code_i(4 * blk + 3, 4 * blk)
    val (ca, cb) = if (n % 2 == 0) (nib(1, 0), nib(3, 2)) else (nib(3, 2), nib(1, 0))
    val caNz = ca(0)
    val cbNz = cb(0)
    val s = io.sel_o(n)(p)
    s.en := caNz || cbNz
    s.neg := Mux(caNz, ca(1), cb(1))
    s.sel := Mux(
      caNz && cbNz,
      Mux(ca(1) === cb(1), QcGemm.SUM.U, QcGemm.DIFF.U), // ca == cb -> ca*s ; ca == -cb -> ca*d
      Mux(caNz, QcGemm.X_EVEN.U, QcGemm.X_ODD.U)
    )
  }
}

// Per row: subtraction (as the dense Tile: a.asSInt -& subtraction_a.asSInt) and the butterfly.
class QcRowButterfly(params: GemmParams) extends Module with RequireAsyncReset {
  val P = QcGemm.pairs(params)
  val W = QcGemm.sWidth(params)
  val io = IO(new Bundle {
    val a_i = Input(Vec(params.tileSize, UInt(params.dataWidthA.W)))
    val subtraction_a_i = Input(UInt(params.dataWidthA.W))
    val cand_o = Output(Vec(P, Vec(4, SInt(W.W)))) // [x_2p, x_2p+1, s_p, d_p]
  })
  val x = io.a_i.map(a => (a.asSInt -& io.subtraction_a_i.asSInt).asSInt)
  for (p <- 0 until P) {
    io.cand_o(p)(QcGemm.X_EVEN) := x(2 * p)
    io.cand_o(p)(QcGemm.X_ODD) := x(2 * p + 1)
    io.cand_o(p)(QcGemm.SUM) := x(2 * p) +& x(2 * p + 1)
    io.cand_o(p)(QcGemm.DIFF) := x(2 * p) -& x(2 * p + 1)
  }
}

class QcTileIO(params: GemmParams) extends Bundle {
  val cand_i = Input(Vec(QcGemm.pairs(params), Vec(4, SInt(QcGemm.sWidth(params).W))))
  val sel_i = Input(Vec(QcGemm.pairs(params), new QcSel))
  val data_c_i = Input(UInt(params.dataWidthC.W))
  val data_d_o = Output(SInt(params.dataWidthC.W))
  val ctrl = new GemmArrayCtrlIO(params)
}

// Tile (m, n): 4 muxes + 3 adders; control and accumulator identical to snax_acc.gemm.Tile.
class QcTile(params: GemmParams) extends Module with RequireAsyncReset {
  val io = IO(new QcTileIO(params))

  val accumulation_reg = RegInit(0.S(params.dataWidthAccum.W))

  val data_i_fire = WireInit(0.B)
  val data_i_fire_reg = RegInit(0.B)

  val keep_output = RegInit(false.B)

  val mul_add_result = Wire(SInt(params.dataWidthAccum.W))
  chisel3.dontTouch(mul_add_result)

  data_i_fire := io.ctrl.dotprod_a_b === 1.B && io.ctrl.a_b_c_ready_o === 1.B
  data_i_fire_reg := data_i_fire

  val add_c_fire = WireInit(0.B)
  add_c_fire := io.ctrl.add_c_i === 1.B && io.ctrl.a_b_c_ready_o === 1.B
  val add_c_fire_reg = RegInit(0.B)
  add_c_fire_reg := add_c_fire

  keep_output := io.ctrl.d_valid_o && !io.ctrl.d_ready_i

  // select-sum: sum_p sel(code[n][p])
  val terms = (0 until QcGemm.pairs(params)).map { p =>
    val s = io.sel_i(p)
    val v = io.cand_i(p)(s.sel)
    Mux(s.en, Mux(s.neg, 0.S -& v, v), 0.S)
  }
  mul_add_result := terms.reduce(_ +& _)

  when(add_c_fire && io.ctrl.accumulate_i === 0.B) {
    accumulation_reg := io.data_c_i.asSInt
  }
  when(add_c_fire && io.ctrl.accumulate_i === 1.B) {
    accumulation_reg := accumulation_reg + io.data_c_i.asSInt
  }
    .elsewhen(data_i_fire === 1.B && io.ctrl.accumulate_i === 0.B) {
      accumulation_reg := mul_add_result
    }
    .elsewhen(data_i_fire === 1.B && io.ctrl.accumulate_i === 1.B) {
      accumulation_reg := accumulation_reg + mul_add_result
    }

  io.data_d_o := accumulation_reg
  io.ctrl.d_valid_o := add_c_fire_reg || data_i_fire_reg || keep_output
  io.ctrl.a_b_c_ready_o := !keep_output && !(io.ctrl.d_valid_o && !io.ctrl.d_ready_i)
}

class QcMeshIO(params: GemmParams) extends Bundle {
  val data_a_i = Input(Vec(params.meshRow, Vec(params.tileSize, UInt(params.dataWidthA.W))))
  val data_b_i = Input(UInt(QcGemm.codeWidth(params).W))
  val data_c_i = Input(Vec(params.meshRow, Vec(params.meshCol, UInt(params.dataWidthC.W))))
  val data_d_o = Output(Vec(params.meshRow, Vec(params.meshCol, SInt(params.dataWidthC.W))))
  val ctrl = new GemmArrayCtrlIO(params)
}

class QcMesh(params: GemmParams) extends Module with RequireAsyncReset {
  QcGemm.check(params)
  val io = IO(new QcMeshIO(params))
  chisel3.dontTouch(io)

  val rows = Seq.fill(params.meshRow)(Module(new QcRowButterfly(params)))
  val decoder = Module(new QcColumnDecoder(params))
  decoder.io.code_i := io.data_b_i
  for (r <- 0 until params.meshRow) {
    rows(r).io.a_i := io.data_a_i(r)
    rows(r).io.subtraction_a_i := io.ctrl.subtraction_a_i
  }

  val mesh = Seq.fill(params.meshRow, params.meshCol)(Module(new QcTile(params)))
  for (r <- 0 until params.meshRow; c <- 0 until params.meshCol) {
    val t = mesh(r)(c).io
    t.cand_i := rows(r).io.cand_o
    t.sel_i := decoder.io.sel_o(c)
    t.data_c_i := io.data_c_i(r)(c)
    io.data_d_o(r)(c) := t.data_d_o
    t.ctrl.dotprod_a_b := io.ctrl.dotprod_a_b
    t.ctrl.add_c_i := io.ctrl.add_c_i
    t.ctrl.accumulate_i := io.ctrl.accumulate_i
    t.ctrl.d_ready_i := io.ctrl.d_ready_i
    t.ctrl.subtraction_a_i := io.ctrl.subtraction_a_i
    t.ctrl.subtraction_b_i := io.ctrl.subtraction_b_i // unused by the QC tile
  }
  io.ctrl.d_valid_o := mesh(0)(0).io.ctrl.d_valid_o
  io.ctrl.a_b_c_ready_o := mesh(0)(0).io.ctrl.a_b_c_ready_o
}

class QcGemmDataIO(params: GemmParams) extends Bundle {
  val a_i = Input(UInt((params.meshRow * params.tileSize * params.dataWidthA).W))
  val b_i = Input(UInt(QcGemm.codeWidth(params).W))
  val c_i = Input(UInt((params.meshRow * params.meshCol * params.dataWidthC).W))
  val d_o = Output(UInt((params.meshRow * params.meshCol * params.dataWidthC).W))
}

class QcGemmArrayIO(params: GemmParams) extends Bundle {
  val ctrl = new GemmArrayCtrlIO(params)
  val data = new QcGemmDataIO(params)
}

// Same A / C / D bit layout as snax_acc.gemm.GemmArray; B is the code word.
class QcGemmArray(params: GemmParams) extends Module with RequireAsyncReset {
  val io = IO(new QcGemmArrayIO(params))
  val mesh = Module(new QcMesh(params))

  for (r <- 0 until params.meshRow; c <- 0 until params.tileSize) {
    mesh.io.data_a_i(r)(c) := io.data.a_i(
      (r * params.tileSize + c + 1) * params.dataWidthA - 1,
      (r * params.tileSize + c) * params.dataWidthA
    )
  }
  mesh.io.data_b_i := io.data.b_i
  for (r <- 0 until params.meshRow; c <- 0 until params.meshCol) {
    mesh.io.data_c_i(r)(c) := io.data.c_i(
      (r * params.meshCol + c + 1) * params.dataWidthC - 1,
      (r * params.meshCol + c) * params.dataWidthC
    )
  }
  val d_rows = (0 until params.meshRow).map(r => Cat(mesh.io.data_d_o(r).map(_.asUInt).reverse))
  io.data.d_o := Cat(d_rows.reverse)
  mesh.io.ctrl <> io.ctrl
}
