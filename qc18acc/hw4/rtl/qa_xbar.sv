// v4 activation crossbar (bank -> pixel row) as a staged log shifter (ARCH addendum "distributed activation
// crossbar"), kw window on 16 slots, code register.  Pipeline (AGU issue in cycle t, S1 control at t+1):
//   t+4  bank-select registers in qa_actmem4: ar_rdata[b] = pair word of bank b (loaded only for the banks read)
//   t+5  stage A registers:  sa[i] = ar_rdata[(i + rot[1:0]) mod 16]          (4:1, loaded if that bank was read)
//   t+6  window registers:   W[j] = rd[j] ? sa[(j + 4 rot[3:2]) mod 16]        (4:1)
//                                   : shift ? W[j + 1] : W[j]                 (slot j = index B + j, raw words)
//        row p = lane[p] ? W[p] : 0 (registered lane mask at the array input); code register (t+6): column g =
//        {odd code, even code} = bits [10g+9 : 10g] of the odd / even weight words read at t+2 (valid t+5).
// sa[i] holds bank (i + rot[1:0]) and W[j] takes sa[j + 4 rot[3:2]] = bank (j + rot) mod 16 as the v3 rotation.
// Widest fan-in: 4 sources per stage-A bit, 4 + shift + hold per window bit (v3: 8 banks x 3 buffers per window bit).
module qa_xbar import qa_pkg::*; (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   s1_vld, s1_first, s1_last,
  input  logic [LNB-1:0]         s1_rot,
  input  logic [NROW-1:0]        s1_lane,
  input  logic [NROW-1:0]        s1_rd,
  input  logic [NBANK-1:0]       s1_ce,
  input  logic                   s1_shift,
  input  logic [NBANK*128-1:0]   ar_rdata,     // t+4: bank b pair word
  input  logic [WBITS-1:0]       we_rdata,     // t+5: even weight word
  input  logic [WBITS-1:0]       wo_rdata,     // t+5: odd weight word
  output logic                   s3_vld, s3_first, s3_last,   // t+6 (array stage)
  output logic [NROW*128-1:0]    s3_x,
  output logic [8*20-1:0]        s3_code
);
  // control delay line: index d = valid in cycle t+d (d = 2..6)
  logic [6:2] v, fi, la, sh;
  logic [LNB-1:0] rot [2:5];
  logic [NROW-1:0] lane [2:6];
  logic [NROW-1:0] rdm [2:5];
  logic [NBANK-1:0] cem [2:4];
  always_ff @(posedge clk) begin
    if (!rst_n) v <= '0;
    else v <= {v[5:2], s1_vld};
    fi <= {fi[5:2], s1_first}; la <= {la[5:2], s1_last}; sh <= {sh[5:2], s1_shift};
    rot[2] <= s1_rot; lane[2] <= s1_lane; rdm[2] <= s1_rd; cem[2] <= s1_ce;
    for (int d = 3; d <= 5; d++) begin rot[d] <= rot[d-1]; rdm[d] <= rdm[d-1]; end
    for (int d = 3; d <= 6; d++) lane[d] <= lane[d-1];
    for (int d = 3; d <= 4; d++) cem[d] <= cem[d-1];
  end
  assign s3_vld = v[6];
  assign s3_first = fi[6];
  assign s3_last = la[6];

  // stage A (loaded at the end of t+4 from the bank-select registers)
  logic [NROW*128-1:0] sa;
  always_ff @(posedge clk)
    if (v[4])
      for (int i = 0; i < NROW; i++) begin
        logic [LNB-1:0] src;
        src = LNB'(i + rot[4][1:0]);
        if (cem[4][src]) sa[i*128 +: 128] <= ar_rdata[src*128 +: 128];
      end

  // window (loaded at the end of t+5), code register
  logic [NROW*128-1:0] win;
  wire  [NROW*128-1:0] win_sh = {128'd0, win[NROW*128-1:128]};
  always_ff @(posedge clk)
    if (v[5]) begin
      for (int j = 0; j < NROW; j++)
        if (rdm[5][j]) win[j*128 +: 128] <= sa[LNB'(j + {rot[5][3:2], 2'b00})*128 +: 128];
        else if (sh[5]) win[j*128 +: 128] <= win_sh[j*128 +: 128];
      for (int g = 0; g < 8; g++) s3_code[g*20 +: 20] <= {wo_rdata[g*10 +: 10], we_rdata[g*10 +: 10]};
    end
  always_comb
    for (int p = 0; p < NROW; p++) s3_x[p*128 +: 128] = lane[6][p] ? win[p*128 +: 128] : 128'd0;
endmodule
