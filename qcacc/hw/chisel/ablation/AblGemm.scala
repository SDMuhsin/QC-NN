package snax_acc.ablation

// Array-level ablation (qcacc/ARCH.md "Comparisons", M4): three standalone 8x8x8 GeMM cores with the SAME
// control, input cut, accumulators, add-C and A / C / D interfaces; only the array datapath and the B width differ.
//   dense   : snax_acc.gemm.GemmArray (upstream int8 MAC tiles, B 512 b)
//   ternary : TernaryGemmArray (8 terms {0, +x, -x} per tile, 2-bit weights, B 128 b; no butterfly)
//   qc      : snax_acc.qcgemm.QcGemmArray (butterfly + 4-term select, B 64 b)
// AblBlockGemm is snax_acc.gemm.BlockGemm (= QcBlockGemm) verbatim with the array behind a common IO.
//   runMain snax_acc.ablation.AblGemmEmit <dense|ternary|qc> <dir>   -> <dir>/AblGemm_<variant>.sv

import chisel3._
import chisel3.util._

import snax_acc.gemm._
import snax_acc.qcgemm._
import snax_acc.utils._
import snax_acc.utils.DecoupledCut._

object Ternary {
  // B: one 2-bit trit per (column n, k) at bits [16 n + 2 k + 1 : 16 n + 2 k]; 00 = 0, 01 = +1, 11 = -1 (10 = 0)
  def codeWidth(p: GemmParams): Int = 2 * p.meshCol * p.tileSize
}

// Tile (m, n): sum_k {0, +x_k, -x_k}, x_k = a_k - subtraction_a shared per row (as QcRowButterfly's x, no s / d).
// Accumulator, add-C and valid / ready control: snax_acc.gemm.Tile line for line.
class TernaryTile(params: GemmParams) extends Module with RequireAsyncReset {
  val io = IO(new Bundle {
    val x_i = Input(Vec(params.tileSize, SInt((params.dataWidthA + 1).W)))
    val w_i = Input(Vec(params.tileSize, UInt(2.W)))
    val data_c_i = Input(UInt(params.dataWidthC.W))
    val data_d_o = Output(SInt(params.dataWidthC.W))
    val ctrl = new GemmArrayCtrlIO(params)
  })

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

  // 8 sign-selects + 7 adders
  val terms = (0 until params.tileSize).map { k =>
    val w = io.w_i(k)
    val x = io.x_i(k)
    Mux(w(0), Mux(w(1), 0.S -& x, x), 0.S)
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

// Common array IO of the three variants (A / C / D bit layout = snax_acc.gemm.GemmArray).
class AblArrayIO(params: GemmParams, bW: Int) extends Bundle {
  val ctrl = new GemmArrayCtrlIO(params)
  val a_i = Input(UInt((params.meshRow * params.tileSize * params.dataWidthA).W))
  val b_i = Input(UInt(bW.W))
  val c_i = Input(UInt((params.meshRow * params.meshCol * params.dataWidthC).W))
  val d_o = Output(UInt((params.meshRow * params.meshCol * params.dataWidthC).W))
}

abstract class AblArray(params: GemmParams, val bW: Int) extends Module with RequireAsyncReset {
  val io = IO(new AblArrayIO(params, bW))
}

class TernaryGemmArray(params: GemmParams) extends AblArray(params, Ternary.codeWidth(params)) {
  val xw = params.dataWidthA + 1
  // per row: x_k = a_k - subtraction_a (dense Tile's subtraction, shared by the 8 columns)
  val x = Seq.tabulate(params.meshRow, params.tileSize) { (r, k) =>
    val a = io.a_i((r * params.tileSize + k + 1) * params.dataWidthA - 1, (r * params.tileSize + k) * params.dataWidthA)
    (a.asSInt -& io.ctrl.subtraction_a_i.asSInt).asSInt
  }
  val mesh = Seq.fill(params.meshRow, params.meshCol)(Module(new TernaryTile(params)))
  for (r <- 0 until params.meshRow; c <- 0 until params.meshCol) {
    val t = mesh(r)(c).io
    for (k <- 0 until params.tileSize) {
      t.x_i(k) := x(r)(k)
      t.w_i(k) := io.b_i(2 * (c * params.tileSize + k) + 1, 2 * (c * params.tileSize + k))
    }
    t.data_c_i := io.c_i((r * params.meshCol + c + 1) * params.dataWidthC - 1, (r * params.meshCol + c) * params.dataWidthC)
    t.ctrl.dotprod_a_b := io.ctrl.dotprod_a_b
    t.ctrl.add_c_i := io.ctrl.add_c_i
    t.ctrl.accumulate_i := io.ctrl.accumulate_i
    t.ctrl.d_ready_i := io.ctrl.d_ready_i
    t.ctrl.subtraction_a_i := io.ctrl.subtraction_a_i
    t.ctrl.subtraction_b_i := io.ctrl.subtraction_b_i // unused
  }
  val d_rows = (0 until params.meshRow).map(r => Cat(mesh(r).map(_.io.data_d_o.asUInt).reverse))
  io.d_o := Cat(d_rows.reverse)
  io.ctrl.d_valid_o := mesh(0)(0).io.ctrl.d_valid_o
  io.ctrl.a_b_c_ready_o := mesh(0)(0).io.ctrl.a_b_c_ready_o
}

// wrappers: wires only
class DenseAblArray(params: GemmParams)
    extends AblArray(params, params.tileSize * params.meshCol * params.dataWidthB) {
  val g = Module(new GemmArray(params))
  g.io.ctrl <> io.ctrl
  g.io.data.a_i := io.a_i
  g.io.data.b_i := io.b_i
  g.io.data.c_i := io.c_i
  io.d_o := g.io.data.d_o
}

class QcAblArray(params: GemmParams) extends AblArray(params, QcGemm.codeWidth(params)) {
  val g = Module(new QcGemmArray(params))
  g.io.ctrl <> io.ctrl
  g.io.data.a_i := io.a_i
  g.io.data.b_i := io.b_i
  g.io.data.c_i := io.c_i
  io.d_o := g.io.data.d_o
}

class AblBlockGemmDataIO(params: GemmParams, bW: Int) extends Bundle {
  val a_i = Flipped(DecoupledIO(UInt((params.meshRow * params.tileSize * params.dataWidthA).W)))
  val b_i = Flipped(DecoupledIO(UInt(bW.W)))
  val c_i = Flipped(DecoupledIO(UInt((params.meshRow * params.meshCol * params.dataWidthC).W)))
  val d_o = DecoupledIO(UInt((params.meshRow * params.meshCol * params.dataWidthC).W))
}

class AblBlockGemmIO(params: GemmParams, bW: Int) extends Bundle {
  val ctrl = Flipped(DecoupledIO(new BlockGemmCtrlIO(params)))
  val data = new AblBlockGemmDataIO(params, bW)
  val busy_o = Output(Bool())
  val performance_counter = Output(UInt(32.W))
}

class AblBlockGemm(params: GemmParams, variant: String, mk: => AblArray) extends Module with RequireAsyncReset {
  override def desiredName = s"AblGemm_$variant"

  val gemm_array = Module(mk)
  val io = IO(new AblBlockGemmIO(params, gemm_array.bW))


  // Registers to store the configurations
  val M = RegInit(0.U(params.sizeConfigWidth.W))
  val K = RegInit(0.U(params.sizeConfigWidth.W))
  val N = RegInit(0.U(params.sizeConfigWidth.W))

  val subtraction_a = RegInit(0.U(params.dataWidthA.W))
  val subtraction_b = RegInit(0.U(params.dataWidthB.W))

  // useful counters
  val compute_fire_counter = RegInit(0.U((params.sizeConfigWidth).W))
  // counter used to record if need to output to outside
  val d_output_ifvalid_counter = RegInit(0.U(params.sizeConfigWidth.W))
  // counter to record how many output data has been written
  val d_output_counter = RegInit(0.U((2 * params.sizeConfigWidth).W))

  val performance_counter = RegInit(0.U(32.W))

  // control signals for the counter incremental
  val accumulation = WireInit(0.B)
  val a_b_data_valid = WireInit(0.B)
  val a_b_data_ready = WireInit(0.B)

  val gemm_a_b_input_fire = WireInit(0.B)
  val gemm_output_fire = WireInit(0.B)

  // add c control signal genertaion
  // in the middle of the K accumulation
  val needs_add_c = RegInit(1.B)
  // after the K accumulation, waiting for add C matrix
  val must_add_c = WireInit(0.B)
  // wire for the addition control signal
  val add_c = WireInit(0.B)
  val add_c_fire = WireInit(0.B)

  val compute_fire = WireInit(0.B)

  // State declaration
  val sIDLE :: sBUSY :: Nil = Enum(2)
  val cstate = RegInit(sIDLE)
  val nstate = WireInit(sIDLE)

  // signals for state transition
  val config_valid = WireInit(0.B)
  val computation_finish = WireInit(0.B)

  val zeroLoopBoundCase = WireInit(0.B)
  zeroLoopBoundCase := io.ctrl.bits.M_i === 0.U || io.ctrl.bits.K_i === 0.U || io.ctrl.bits.K_i === 0.U

  // Changing states
  cstate := nstate

  chisel3.dontTouch(cstate)
  switch(cstate) {
    is(sIDLE) {
      when(config_valid && !zeroLoopBoundCase) {
        nstate := sBUSY
      }.otherwise {
        nstate := sIDLE
      }

    }
    is(sBUSY) {
      when(computation_finish) {
        nstate := sIDLE
      }.otherwise {
        nstate := sBUSY
      }
    }
  }

  config_valid := io.ctrl.fire

  // Store the configurations when config valid
  when(config_valid && cstate === sIDLE) {
    when(!zeroLoopBoundCase) {
      M := io.ctrl.bits.M_i
      N := io.ctrl.bits.N_i
      K := io.ctrl.bits.K_i
    }.otherwise {
      assert(
        io.ctrl.bits.M_i =/= 0.U || io.ctrl.bits.K_i =/= 0.U || io.ctrl.bits.K_i =/= 0.U,
        " M == 0 or K ==0 or N == 0, invalid configuration!"
      )
    }
    subtraction_a := io.ctrl.bits.subtraction_constant_i(7, 0)
    subtraction_b := io.ctrl.bits.subtraction_constant_i(15, 8)
  }

  // write all the results out means the operation is done
  computation_finish := d_output_counter === (M * N - 1.U) && io.data.d_o.fire && cstate === sBUSY

  // -----------------------------------
  // resgiter insert
  // -----------------------------------

  def a_bits_len = params.meshRow * params.tileSize * params.dataWidthA
  def b_bits_len = gemm_array.bW
  def sa_bits_len = params.dataWidthA
  def sb_bits_len = params.dataWidthB

  val combined_decoupled_a_b_in = Wire(
    Decoupled(new CutBundle(a_bits_len, b_bits_len, sa_bits_len, sb_bits_len))
  )
  val combined_decoupled_a_b_out = Wire(
    Decoupled(new CutBundle(a_bits_len, b_bits_len, sa_bits_len, sb_bits_len))
  )
  val a_split_out = Wire(UInt(a_bits_len.W))
  val b_split_out = Wire(UInt(b_bits_len.W))
  val subtraction_a_split_out = Wire(UInt(sa_bits_len.W))
  val subtraction_b_split_out = Wire(UInt(sb_bits_len.W))

  val decoupled_subtraction_a = Wire(Decoupled(UInt(sa_bits_len.W)))
  val decoupled_subtraction_b = Wire(Decoupled(UInt(sb_bits_len.W)))

  val a_b_sa_sb_cat = Module(
    new DecoupledCat4to1(a_bits_len, b_bits_len, sa_bits_len, sb_bits_len)
  )

  // cat several decoupled signals into one for synchronization
  a_b_sa_sb_cat.io.in1 <> io.data.a_i
  a_b_sa_sb_cat.io.in2 <> io.data.b_i
  a_b_sa_sb_cat.io.in3 <> decoupled_subtraction_a
  a_b_sa_sb_cat.io.in4 <> decoupled_subtraction_b
  a_b_sa_sb_cat.io.out <> combined_decoupled_a_b_in

  // insert registers
  combined_decoupled_a_b_in -\\> combined_decoupled_a_b_out
  a_split_out := combined_decoupled_a_b_out.bits.a
  b_split_out := combined_decoupled_a_b_out.bits.b
  subtraction_a_split_out := combined_decoupled_a_b_out.bits.c
  subtraction_b_split_out := combined_decoupled_a_b_out.bits.d
  // combined_decoupled_a_b_out will be connected to further control signals

  decoupled_subtraction_a.valid := cstate === sBUSY
  decoupled_subtraction_a.bits := subtraction_a
  decoupled_subtraction_b.valid := cstate === sBUSY
  decoupled_subtraction_b.bits := subtraction_b

  // write counter increment according to output data fire
  when(io.data.d_o.fire) {
    d_output_counter := d_output_counter + 1.U
  }.elsewhen(cstate === sIDLE) {
    d_output_counter := 0.U
  }

  // input data valid signal, when both a and b are valid, the input data is valid
  a_b_data_valid := combined_decoupled_a_b_out.valid && cstate === sBUSY
  a_b_data_ready := gemm_array.io.ctrl.a_b_c_ready_o && cstate === sBUSY

  // gemm input fire signal, when both a and b are valid and gemm is ready for new input data
  // stall the a b compute if add c
  gemm_a_b_input_fire := a_b_data_ready && a_b_data_valid && !add_c && !must_add_c

  // accumulation counter for generating the accumulation signal for Gemm Array
  // value change according to gemm_a_b_input_fire and add_c_fire
  // (K + 1) computation for 1 reset compute_fire_counter
  compute_fire := gemm_a_b_input_fire || add_c_fire
  when(
    compute_fire && compute_fire_counter =/= K && cstate =/= sIDLE
  ) {
    compute_fire_counter := compute_fire_counter + 1.U
  }.elsewhen(
    compute_fire && compute_fire_counter === K && cstate =/= sIDLE
  ) {
    compute_fire_counter := 0.U
  }.elsewhen(cstate === sIDLE) {
    compute_fire_counter := 0.U
  }

  // accumulation control signal
  // only clean the accumulation register once
  accumulation := compute_fire_counter =/= 0.U

  when(cstate === sBUSY) {
    performance_counter := performance_counter + 1.U
  }.elsewhen(config_valid) {
    performance_counter := 0.U
  }

  // gemm output fire signal, asserted when gemm is fire for outputting the result
  gemm_output_fire := gemm_array.io.ctrl.d_valid_o && gemm_array.io.ctrl.d_ready_i

  // with add C support, now needs K + 1 times acclumation for 1 write
  // (K + 1) computation for 1 reset d_output_ifvalid_counter
  when(
    gemm_output_fire && d_output_ifvalid_counter =/= K && cstate =/= sIDLE
  ) {
    d_output_ifvalid_counter := d_output_ifvalid_counter + 1.U
  }.elsewhen(
    gemm_output_fire && d_output_ifvalid_counter === K && cstate =/= sIDLE
  ) {
    d_output_ifvalid_counter := 0.U
  }.elsewhen(cstate === sIDLE) {
    d_output_ifvalid_counter := 0.U
  }

  // add c control signal generation
  when(add_c_fire) {
    needs_add_c := 0.B
  }.elsewhen(
    // shift needs_add_c to 1 after d valid. it's safe to shift after one cycle as K == 1 at minimum.
    io.data.d_o.valid
  ) {
    needs_add_c := 1.B
  }

  // after K a b dotprod, must need to add c before continue
  // related to input situation
  must_add_c := needs_add_c && (compute_fire_counter === K)

  add_c := cstate === sBUSY && ((needs_add_c && !a_b_data_valid) || must_add_c) && io.data.c_i.valid
  add_c_fire := add_c && gemm_array.io.ctrl.a_b_c_ready_o

  // output control signals for read-only csrs
  io.performance_counter := performance_counter

  io.busy_o := cstate =/= sIDLE

  io.ctrl.ready := cstate === sIDLE

  // Gemm Array signal connection
  // control signals
  gemm_array.io.ctrl.dotprod_a_b := a_b_data_valid && !add_c && !must_add_c
  gemm_array.io.ctrl.add_c_i := add_c
  gemm_array.io.ctrl.accumulate_i := accumulation
  // grap gemm output out
  // when the d fifo is ready for new data
  // or when don't need to output d
  gemm_array.io.ctrl.d_ready_i := Mux(io.data.d_o.valid, io.data.d_o.ready, 1.B)

  gemm_array.io.ctrl.subtraction_a_i := subtraction_a_split_out
  gemm_array.io.ctrl.subtraction_b_i := subtraction_b_split_out

  // data signals
  gemm_array.io.a_i := a_split_out
  gemm_array.io.b_i := b_split_out
  gemm_array.io.c_i := io.data.c_i.bits

  combined_decoupled_a_b_out.ready := cstate === sBUSY && gemm_a_b_input_fire

  io.data.c_i.ready := cstate === sBUSY && add_c_fire

  // gemm output signals
  io.data.d_o.bits := gemm_array.io.d_o
  // after K + 1 times accumulation, the output is valid
  io.data.d_o.valid := (d_output_ifvalid_counter === K) && gemm_array.io.ctrl.d_valid_o && cstate =/= sIDLE

}


object AblGemmEmit {
  def main(args: Array[String]): Unit = {
    val p = DefaultConfig.gemmConfig
    val v = args(0)
    def mk: AblArray = v match {
      case "dense"   => new DenseAblArray(p)
      case "ternary" => new TernaryGemmArray(p)
      case "qc"      => new QcAblArray(p)
    }
    emitVerilog(new AblBlockGemm(p, v, mk), Array("--target-dir", args(1)))
  }
}
