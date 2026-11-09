// Descriptor sequencer: START -> for each descriptor (8 x 32-b words, Appendix) fetch, decode, run the conv pass
// (AGU + drain / PPU) or the head, until the descriptor with `last`.  Holds the perf counters.
// Descriptor fetch: 8 reads + 1 cycle (pipelined, registered RAM output), then a 1-cycle launch that registers
// the derived fields (log2 of the power-of-two map sizes).
module qa_seq import qa_pkg::*; (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 start,
  output logic                 busy,
  output logic                 done,
  // descriptor RAM read port
  output logic                 d_ce,
  output logic [DAW-1:0]       d_addr,
  input  logic [31:0]          d_rdata,
  // decoded fields (stable during a pass)
  output logic [1:0]           f_k, f_stride, f_mode,
  output logic                 f_in_lay, f_out_lay, f_res_lay,
  output logic [1:0]           f_in_buf, f_out_buf, f_res_buf,
  output logic [7:0]           f_hin, f_win, f_hout, f_wout,
  output logic [3:0]           f_lhi, f_lwi, f_lho, f_lwo,
  output logic [7:0]           f_cin8, f_cout64,
  output logic [AAW-1:0]       f_in_base, f_out_base, f_res_base,
  output logic [WAW-1:0]       f_wbase,
  output logic [PAW-1:0]       f_pbase,
  output logic [30:0]          f_m0,         // idm0 (RES_ID) or pool m0 (head)
  output logic [5:0]           f_sh,         // idsh (RES_ID) or pool sh (head)
  // pass control
  output logic                 conv_start,
  input  logic                 conv_done,
  output logic                 head_start,
  input  logic                 head_done,
  output logic                 head_active,
  output logic                 pass_done,    // 1-cycle pulse at the end of every conv pass (and the head)
  output logic [4:0]           pass_idx,
  // perf
  input  logic                 ev_busy, ev_stall, ev_pload,
  output logic [31:0]          cyc_total, cyc_busy, cyc_stall, cyc_pload,
  output logic [5:0]           npass,
  output logic [MAXPASS*32-1:0] cyc_pass
);
  typedef enum logic [2:0] {S_IDLE, S_FETCH, S_LAUNCH, S_CONV, S_HEAD} st_t;
  st_t st;
  logic [3:0]  fcnt;
  logic [31:0] dw [0:7];
  logic [31:0] pcyc;

  function automatic logic [3:0] lg2(input logic [7:0] v);
    lg2 = 4'd0;
    for (int i = 0; i < 8; i++) if (v[i]) lg2 = 4'(i);
  endfunction

  // fields straight from the descriptor words (registers)
  assign f_k        = dw[0][3:2];
  assign f_stride   = dw[0][5:4];
  assign f_mode     = dw[0][7:6];
  assign f_in_lay   = dw[0][8];
  assign f_out_lay  = dw[0][9];
  assign f_res_lay  = dw[0][10];
  assign f_in_buf   = dw[0][12:11];
  assign f_out_buf  = dw[0][14:13];
  assign f_res_buf  = dw[0][16:15];
  assign f_hin      = dw[1][7:0];
  assign f_win      = dw[1][15:8];
  assign f_hout     = dw[1][23:16];
  assign f_wout     = dw[1][31:24];
  assign f_cin8     = dw[2][7:0];
  assign f_cout64   = dw[2][23:16];
  assign f_in_base  = dw[3][9:0];
  assign f_out_base = dw[3][19:10];
  assign f_res_base = dw[3][29:20];
  assign f_wbase    = dw[4][WAW-1:0];
  assign f_pbase    = dw[5][PAW-1:0];
  assign f_m0       = dw[6][30:0];
  assign f_sh       = dw[7][5:0];

  assign d_ce   = st == S_FETCH && fcnt < 4'd8;
  assign d_addr = DAW'({pass_idx, 3'b000} + fcnt);
  assign busy   = st != S_IDLE;
  assign head_active = st == S_HEAD;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= S_IDLE; done <= 1'b0; fcnt <= '0; pass_idx <= '0; conv_start <= 1'b0; head_start <= 1'b0;
      pass_done <= 1'b0; pcyc <= '0; npass <= '0;
      cyc_total <= '0; cyc_busy <= '0; cyc_stall <= '0; cyc_pload <= '0; cyc_pass <= '0;
      f_lhi <= '0; f_lwi <= '0; f_lho <= '0; f_lwo <= '0;
      for (int i = 0; i < 8; i++) dw[i] <= '0;
    end else begin
      conv_start <= 1'b0; head_start <= 1'b0; pass_done <= 1'b0;
      if (busy) begin
        cyc_total <= cyc_total + 1;
        pcyc      <= pcyc + 1;
        cyc_busy  <= cyc_busy + 32'(ev_busy);
        cyc_stall <= cyc_stall + 32'(ev_stall);
        cyc_pload <= cyc_pload + 32'(ev_pload);
      end
      case (st)
        S_IDLE: if (start) begin
          st <= S_FETCH; done <= 1'b0; fcnt <= '0; pass_idx <= '0; pcyc <= '0; npass <= '0;
          cyc_total <= '0; cyc_busy <= '0; cyc_stall <= '0; cyc_pload <= '0; cyc_pass <= '0;
        end
        S_FETCH: begin
          if (fcnt != 0) dw[fcnt - 1] <= d_rdata;
          fcnt <= fcnt + 1;
          if (fcnt == 4'd8) st <= S_LAUNCH;
        end
        S_LAUNCH: begin
          f_lhi <= lg2(f_hin); f_lwi <= lg2(f_win); f_lho <= lg2(f_hout); f_lwo <= lg2(f_wout);
          if (dw[0][1:0] == T_HEAD) begin
            st <= S_HEAD; head_start <= 1'b1;
            f_lhi <= lg2(f_hin); f_lwi <= lg2(f_win); f_lho <= lg2(f_hin); f_lwo <= lg2(f_win);
          end else begin
            st <= S_CONV; conv_start <= 1'b1;
          end
        end
        S_CONV: if (conv_done && !conv_start) begin
          pass_done <= 1'b1;
          cyc_pass[pass_idx*32 +: 32] <= pcyc + 1;
          pcyc <= '0; npass <= npass + 1;
          pass_idx <= pass_idx + 1; fcnt <= '0; st <= S_FETCH;
        end
        S_HEAD: if (head_done && !head_start) begin
          pass_done <= 1'b1;
          cyc_pass[pass_idx*32 +: 32] <= pcyc + 1;
          npass <= npass + 1;
          st <= S_IDLE; done <= 1'b1;
        end
        default: st <= S_IDLE;
      endcase
    end
  end
`ifndef SYNTHESIS
  // the hardware assumes power-of-two map sizes (CIFAR ResNet-18: 32 / 16 / 8 / 4) and supported fields
  always @(posedge clk) if (rst_n && st == S_LAUNCH) begin
    if (dw[0][1:0] == T_CONV) begin
      if ((f_hin & (f_hin - 1)) != 0 || (f_win & (f_win - 1)) != 0 || (f_hout & (f_hout - 1)) != 0 ||
          (f_wout & (f_wout - 1)) != 0) $error("qa_seq: pass %0d: map size not a power of two", pass_idx);
      if (!(f_k == 1 || f_k == 3) || !(f_stride == 1 || f_stride == 2) || f_hout * f_wout < 8)
        $error("qa_seq: pass %0d: unsupported k / stride / size", pass_idx);
      if (dw[0][17]) $error("qa_seq: conv descriptor with last");
    end else if (dw[0][1:0] != T_HEAD) $error("qa_seq: pass %0d: bad descriptor type %0d", pass_idx, dw[0][1:0]);
  end
`endif
endmodule
