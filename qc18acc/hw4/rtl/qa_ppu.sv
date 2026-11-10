// v4 PPU unit: 16 lanes (qa_ppu_lane), one 128-b output pair word per cycle with its own act-buffer write port and
// residual read port (qa_actmem4 pw<u> / pr<u>); qa_top instantiates NPPU = 2 units = 32 lanes (two pixels per drain
// read).  v3 qa_ppu re-timed for the registered memory boundaries:
//   D0      drain read (in_vld): residual request (q, or the RES_R low-byte plane) issued combinationally;
//   D0 + 1  RES_R high-byte plane request;  data return in D0 + 5 / D0 + 6 (RLAT);
//   D0 + 8  write request of the output word (r8 registers); RAW16: high-byte plane in the next cycle.
// RES_R / RAW16 accept one word per 2 cycles.  Head mode (unit 0): lanes 0..7 carry the pooled sums of one channel
// group, h_p = lanes 0..7 of r8.  busy covers the pipeline and the 2-cycle write path inside qa_actmem4.
module qa_ppu import qa_pkg::*; (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic [1:0]           mode,
  input  logic                 head,
  input  logic [30:0]          idm0,
  input  logic [5:0]           idsh,
  input  logic                 in_vld,
  input  logic [NL*ACC-1:0]    in_acc,
  input  logic [NL*VW-1:0]     in_bias,
  input  logic [NL*31-1:0]     in_m0,
  input  logic [NL*6-1:0]      in_sh,
  input  logic [NL-1:0]        in_d,
  input  logic [LNB-1:0]       in_obank, in_obank_hi, in_rbank, in_rbank_hi,
  input  logic [AAW-1:0]       in_oaddr, in_oaddr_hi, in_raddr, in_raddr_hi,
  output logic                 pw_we,
  output logic [LNB-1:0]       pw_bank,
  output logic [AAW-1:0]       pw_addr,
  output logic [127:0]         pw_wdata,
  output logic                 pr_re,
  output logic [LNB-1:0]       pr_bank,
  output logic [AAW-1:0]       pr_addr,
  input  logic [127:0]         pr_rdata,
  output logic                 h_vld,
  output logic [63:0]          h_p,
  output logic                 busy
);
  logic [8:1] v;
  logic hi_pend, wq1, wq2;
  logic [LNB-1:0] ob [1:8];
  logic [LNB-1:0] obh [1:8];
  logic [AAW-1:0] oa [1:8];
  logic [AAW-1:0] oah [1:8];
  logic [LNB-1:0] rbh1, hi_bank;
  logic [AAW-1:0] rah1, hi_addr;
  logic [127:0] out8, out8_hi, hi_data;

  wire res_mode = (mode == M_RES_ID || mode == M_RES_R) && !head;
  wire [1:0] lmode = head ? M_RELU : mode;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      v <= '0; hi_pend <= 1'b0; wq1 <= 1'b0; wq2 <= 1'b0;
    end else begin
      v <= {v[7:1], in_vld};
      hi_pend <= v[8] && mode == M_RAW16 && !head;
      wq1 <= pw_we; wq2 <= wq1;
    end
  end
  always_ff @(posedge clk) begin
    if (in_vld) begin
      ob[1] <= in_obank; obh[1] <= in_obank_hi; oa[1] <= in_oaddr; oah[1] <= in_oaddr_hi;
      rbh1 <= in_rbank_hi; rah1 <= in_raddr_hi;
    end
    for (int s = 2; s <= 8; s++) begin
      ob[s] <= ob[s-1]; obh[s] <= obh[s-1]; oa[s] <= oa[s-1]; oah[s] <= oah[s-1];
    end
    if (v[8]) begin hi_bank <= obh[8]; hi_addr <= oah[8]; hi_data <= out8_hi; end
  end

  genvar i;
  for (i = 0; i < NL; i++) begin : g_lane
    qa_ppu_lane u_lane (
      .clk(clk), .en({v[7:1], in_vld}), .mode(lmode),
      .acc(in_acc[i*ACC +: ACC]), .bias(in_bias[i*VW +: VW]), .m0(in_m0[i*31 +: 31]), .sh(in_sh[i*6 +: 6]),
      .d(in_d[i]), .rdat(pr_rdata[i*8 +: 8]), .idm0(idm0), .idsh(idsh),
      .out8(out8[i*8 +: 8]), .out8_hi(out8_hi[i*8 +: 8]));
  end

  assign pr_re   = res_mode && (in_vld || (v[1] && mode == M_RES_R));
  assign pr_bank = in_vld ? in_rbank : rbh1;
  assign pr_addr = in_vld ? in_raddr : rah1;
  assign pw_we    = (v[8] && !head) || hi_pend;
  assign pw_bank  = hi_pend ? hi_bank : ob[8];
  assign pw_addr  = hi_pend ? hi_addr : oa[8];
  assign pw_wdata = hi_pend ? hi_data : out8;
  assign h_vld = v[8] && head;
  assign h_p   = out8[63:0];
  assign busy  = in_vld | (|v) | hi_pend | wq1 | wq2;

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n) begin
    if (v[8] && hi_pend) $error("qa_ppu: RAW16 high-plane write collides with the next word");
    if (res_mode && mode == M_RES_R && in_vld && v[1]) $error("qa_ppu: RES_R words closer than 2 cycles");
  end
`endif
endmodule
