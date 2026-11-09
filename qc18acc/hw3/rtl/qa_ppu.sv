// v3 PPU: 16 lanes (qa_ppu_lane), one 128-b output pair word (16 channels of one pixel) per cycle, no back-pressure.
// v2 qa_ppu (hw/rtl) widened: input word at D0 -> r1 .. r6 -> act-buffer write (both halves of one bank word) in the
// r6 cycle (RAW16: low-byte pair plane in the r6 cycle, high-byte plane in the next cycle).  Residual reads (128 b):
// r1 cycle (q, or R low bytes) and, for RES_R, r2 cycle (R high bytes); RES_R / RAW16 accept one word per 2 cycles.
// Head mode: lanes 0..7 carry the pooled sums of one channel group (lanes 8..15 zero), h_p = lanes 0..7.
module qa_ppu import qa_pkg::*; (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic [1:0]           mode,
  input  logic                 head,
  input  logic [1:0]           out_buf, res_buf,
  input  logic [30:0]          idm0,
  input  logic [5:0]           idsh,
  input  logic                 in_vld,
  input  logic [NL*ACC-1:0]    in_acc,
  input  logic [NL*VW-1:0]     in_bias,
  input  logic [NL*31-1:0]     in_m0,
  input  logic [NL*6-1:0]      in_sh,
  input  logic [NL-1:0]        in_d,
  input  logic [2:0]           in_obank, in_obank_hi, in_rbank, in_rbank_hi,
  input  logic [AAW-1:0]       in_oaddr, in_oaddr_hi, in_raddr, in_raddr_hi,
  output logic                 pw_we,
  output logic [1:0]           pw_buf,
  output logic [2:0]           pw_bank,
  output logic [AAW-1:0]       pw_addr,
  output logic [127:0]         pw_wdata,
  output logic                 pr_re,
  output logic [1:0]           pr_buf,
  output logic [2:0]           pr_bank,
  output logic [AAW-1:0]       pr_addr,
  input  logic [127:0]         pr_rdata,
  output logic                 h_vld,
  output logic [63:0]          h_p,
  output logic                 busy
);
  logic v1, v2, v3, v4, v5, v6, hi_pend;
  logic [2:0] ob [1:6];
  logic [2:0] obh [1:6];
  logic [AAW-1:0] oa [1:6];
  logic [AAW-1:0] oah [1:6];
  logic [2:0] rb1, rbh1, rbh2;
  logic [AAW-1:0] ra1, rah1, rah2;
  logic [2:0] hi_bank;
  logic [AAW-1:0] hi_addr;
  logic [127:0] out6, out6_hi, hi_data;

  wire res_mode = (mode == M_RES_ID || mode == M_RES_R) && !head;
  wire [1:0] lmode = head ? M_RELU : mode;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      {v1, v2, v3, v4, v5, v6, hi_pend} <= '0;
    end else begin
      v1 <= in_vld; v2 <= v1; v3 <= v2; v4 <= v3; v5 <= v4; v6 <= v5;
      hi_pend <= v6 && mode == M_RAW16 && !head;
    end
  end
  always_ff @(posedge clk) begin
    if (in_vld) begin
      ob[1] <= in_obank; obh[1] <= in_obank_hi; oa[1] <= in_oaddr; oah[1] <= in_oaddr_hi;
      rb1 <= in_rbank; rbh1 <= in_rbank_hi; ra1 <= in_raddr; rah1 <= in_raddr_hi;
    end
    if (v1) begin rbh2 <= rbh1; rah2 <= rah1; end
    for (int s = 2; s <= 6; s++) begin
      ob[s] <= ob[s-1]; obh[s] <= obh[s-1]; oa[s] <= oa[s-1]; oah[s] <= oah[s-1];
    end
    if (v6) begin hi_bank <= obh[6]; hi_addr <= oah[6]; hi_data <= out6_hi; end
  end

  genvar i;
  for (i = 0; i < NL; i++) begin : g_lane
    qa_ppu_lane u_lane (
      .clk(clk), .e1(in_vld), .e2(v1), .e3(v2), .e4(v3), .e5(v4), .e6(v5), .mode(lmode),
      .acc(in_acc[i*ACC +: ACC]), .bias(in_bias[i*VW +: VW]), .m0(in_m0[i*31 +: 31]), .sh(in_sh[i*6 +: 6]),
      .d(in_d[i]), .rlo(pr_rdata[i*8 +: 8]), .rhi(pr_rdata[i*8 +: 8]), .idm0(idm0), .idsh(idsh),
      .out6(out6[i*8 +: 8]), .out6_hi(out6_hi[i*8 +: 8]));
  end

  assign pr_re   = res_mode && (v1 || (v2 && mode == M_RES_R));
  assign pr_buf  = res_buf;
  assign pr_bank = v1 ? rb1 : rbh2;
  assign pr_addr = v1 ? ra1 : rah2;
  assign pw_we    = (v6 && !head) || hi_pend;
  assign pw_buf   = out_buf;
  assign pw_bank  = hi_pend ? hi_bank : ob[6];
  assign pw_addr  = hi_pend ? hi_addr : oa[6];
  assign pw_wdata = hi_pend ? hi_data : out6;
  assign h_vld = v6 && head;
  assign h_p   = out6[63:0];
  assign busy  = in_vld | v1 | v2 | v3 | v4 | v5 | v6 | hi_pend;

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n) begin
    if (v6 && hi_pend) $error("qa_ppu: RAW16 high-plane write collides with the next word");
    if (res_mode && mode == M_RES_R && v1 && v2) $error("qa_ppu: RES_R words closer than 2 cycles");
  end
`endif
endmodule
