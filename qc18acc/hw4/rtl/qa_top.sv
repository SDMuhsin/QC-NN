// QC18-ACC v4 top level (qc18acc/ARCH.md "v4" + addendum; v3 = hw3/rtl/qa_top.sv).  Single clock, synchronous
// active-low reset.  v4: 16 pixel rows x 8 columns = 128 v3 PEs (Kb = 2), 16-bank activation buffers (48 x
// 256 x 128 macros), every macro behind a registered boundary (input flops at the macro pins, output register),
// distributed bank -> row crossbar (bank-select / stage A / window registers), two 16-lane PPU units (32 lanes, two
// pixels per drain read), pipelined head FC.
//   qa_host (host port, CSRs) -> qa_seq (descriptors, perf counters) -> per conv pass:
//     qa_agu (S0 requests, S1 control) -> act macros (t+1 pins, t+2 Q, t+3 output regs, t+4 bank select) and weight
//     macros (request t+2, output regs t+5) -> qa_xbar (stage A t+5, window / code t+6) -> qa_array (16 x 8 qa_pe)
//     -> shadow chains A / B -> qa_drain (param RF, 2 pixels per read) -> 2 x qa_ppu (r1..r8) -> act buffer write
//   head: qa_head (pool via PPU unit 0, pipelined FC) -> logits
// Memories: qa_actmem4 (3 x 16 x qa_sram4 256 x 128), weight u_wmem_e / u_wmem_o (each qa_bankmem4 3 x 4096 x 80),
// param u_pmem (qa_bankmem4 2 x 4096 x 72), descriptors u_desc (qa_bankmem4 1 x 256 x 32).
module qa_top import qa_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        host_req,
  input  logic        host_we,
  input  logic [23:0] host_addr,
  input  logic [31:0] host_wdata,
  output logic        host_rvalid,
  output logic [31:0] host_rdata,
  output logic        busy,
  output logic        done
);
  // ---- sequencer fields ----------------------------------------------------------------------------------------
  logic [1:0] f_k, f_stride, f_mode, f_in_buf, f_out_buf, f_res_buf;
  logic f_in_lay, f_out_lay, f_res_lay;
  logic [7:0] f_hin, f_win, f_hout, f_wout, f_cin8, f_cout64;
  logic [3:0] f_lhi, f_lwi, f_lho, f_lwo;
  logic [AAW-1:0] f_in_base, f_out_base, f_res_base;
  logic [WAW-1:0] f_wbase;
  logic [PAW-1:0] f_pbase;
  logic [30:0] f_m0;
  logic [5:0] f_sh;
  logic conv_start, conv_done, head_start, head_done, head_active, pass_done;
  logic [4:0] pass_idx;
  logic [31:0] cyc_total, cyc_busy, cyc_stall, cyc_pload, cnt_ard;
  logic [5:0] npass;
  logic [MAXPASS*32-1:0] cyc_pass;
  logic [MAXCLS*32-1:0] logits;
  logic start;

  // ---- host ----------------------------------------------------------------------------------------------------
  logic hd_ce, hd_we, hp_ce, hp_we, hw_ce, hw_we, hw_half, ha_ce, ha_we, ha_half;
  logic [DAW-1:0] hd_addr;
  logic [31:0] hd_wdata, d_rdata;
  logic [PAW-1:0] hp_addr;
  logic [PBITS-1:0] hp_wdata, p_rdata;
  logic [WAW-1:0] hw_addr;
  logic [WBITS-1:0] hw_wdata, we_rdata, wo_rdata;
  logic [1:0] ha_buf;
  logic [LNB-1:0] ha_bank;
  logic [AAW-1:0] ha_addr;
  logic [63:0] ha_wdata;
  logic [2*128-1:0] pr_rdata;

  qa_host u_host (
    .clk, .rst_n, .host_req, .host_we, .host_addr, .host_wdata, .host_rvalid, .host_rdata,
    .start, .busy, .done,
    .d_ce(hd_ce), .d_we(hd_we), .d_addr(hd_addr), .d_wdata(hd_wdata), .d_rdata(d_rdata),
    .p_ce(hp_ce), .p_we(hp_we), .p_addr(hp_addr), .p_wdata(hp_wdata), .p_rdata(p_rdata),
    .w_ce(hw_ce), .w_we(hw_we), .w_half(hw_half), .w_addr(hw_addr), .w_wdata(hw_wdata), .we_rdata, .wo_rdata,
    .a_ce(ha_ce), .a_we(ha_we), .a_buf(ha_buf), .a_bank(ha_bank), .a_half(ha_half), .a_addr(ha_addr),
    .a_wdata(ha_wdata), .a_rdata(pr_rdata[127:0]),
    .cyc_total, .cyc_busy, .cyc_stall, .cyc_pload, .cnt_ard, .npass, .cyc_pass, .logits);

  // ---- sequencer + descriptor RAM ------------------------------------------------------------------------------
  logic sd_ce;
  logic [DAW-1:0] sd_addr;
  logic ev_busy, ev_stall, ev_pload;
  logic [4:0] ev_ard;
  qa_seq u_seq (
    .clk, .rst_n, .start, .busy, .done, .d_ce(sd_ce), .d_addr(sd_addr), .d_rdata(d_rdata),
    .f_k, .f_stride, .f_mode, .f_in_lay, .f_out_lay, .f_res_lay, .f_in_buf, .f_out_buf, .f_res_buf,
    .f_hin, .f_win, .f_hout, .f_wout, .f_lhi, .f_lwi, .f_lho, .f_lwo, .f_cin8, .f_cout64,
    .f_in_base, .f_out_base, .f_res_base, .f_wbase, .f_pbase, .f_m0, .f_sh,
    .conv_start, .conv_done, .head_start, .head_done, .head_active, .pass_done, .pass_idx,
    .ev_busy, .ev_stall, .ev_pload, .ev_ard, .cyc_total, .cyc_busy, .cyc_stall, .cyc_pload, .cnt_ard, .npass,
    .cyc_pass);
  qa_bankmem4 #(.BANKS(1), .BANK_WORDS(DWORDS), .BITS(32), .AW(DAW)) u_desc (
    .clk, .rst_n, .ce(busy ? sd_ce : hd_ce), .we(!busy && hd_we), .addr(busy ? sd_addr : hd_addr), .wdata(hd_wdata),
    .rdata(d_rdata));

  // ---- array path ----------------------------------------------------------------------------------------------
  logic cap_ok, agu_done, s1_vld, s1_first, s1_last, s1_shift;
  logic [NBANK-1:0] ag_ce, s1_ce;
  logic [NBANK*AAW-1:0] ag_addr;
  logic [LNB-1:0] s1_rot;
  logic [NROW-1:0] s1_lane, s1_rd;
  logic [WAW-1:0] s1_waddr, s2_waddr;
  logic s2_wvld;
  qa_agu u_agu (
    .clk, .rst_n, .start(conv_start), .k(f_k), .stride(f_stride), .lhi(f_lhi), .lwi(f_lwi), .lho(f_lho),
    .lwo(f_lwo), .hin(f_hin), .win(f_win), .cin8(f_cin8), .cout64(f_cout64), .in_base(f_in_base),
    .wbase(f_wbase), .cap_ok, .done(agu_done), .stall(ev_stall), .ar_ce(ag_ce), .ar_addr(ag_addr), .s1_vld,
    .s1_first, .s1_last, .s1_rot, .s1_lane, .s1_rd, .s1_ce, .s1_shift, .s1_waddr);
  always_comb begin                                  // array act-bank reads this cycle (perf counter CSR_ACT_RD)
    ev_ard = '0;
    for (int b = 0; b < NBANK; b++) ev_ard = ev_ard + 5'(ag_ce[b]);
  end
  always_ff @(posedge clk) begin                     // weight request at t+2 (code arrives with the window at t+6)
    if (!rst_n) s2_wvld <= 1'b0;
    else s2_wvld <= s1_vld;
    if (s1_vld) s2_waddr <= s1_waddr;
  end

  logic [NBANK*128-1:0] ar_rdata;
  logic s3_vld, s3_first, s3_last;
  logic [NROW*128-1:0] s3_x;
  logic [8*20-1:0] s3_code;
  qa_xbar u_xbar (
    .clk, .rst_n, .s1_vld, .s1_first, .s1_last, .s1_rot, .s1_lane, .s1_rd, .s1_ce, .s1_shift, .ar_rdata,
    .we_rdata, .wo_rdata, .s3_vld, .s3_first, .s3_last, .s3_x, .s3_code);
  assign ev_busy = s3_vld;

  logic [7:0] shift;
  logic [8*8*ACC-1:0] heads_a, heads_b;
  qa_array u_array (
    .clk, .vld(s3_vld), .first(s3_first), .last(s3_last), .x(s3_x), .code(s3_code), .shift, .heads_a, .heads_b);

  // ---- drain + PPU ---------------------------------------------------------------------------------------------
  logic dm_ce;
  logic [PAW-1:0] dm_addr;
  logic q_vld;
  logic [2*NL*ACC-1:0] q_acc;
  logic [NL*VW-1:0] q_bias;
  logic [NL*31-1:0] q_m0;
  logic [NL*6-1:0] q_sh;
  logic [NL-1:0] q_d;
  logic [2*LNB-1:0] q_obank, q_obank_hi, q_rbank, q_rbank_hi;
  logic [2*AAW-1:0] q_oaddr, q_oaddr_hi, q_raddr, q_raddr_hi;
  logic [1:0] u_busy;
  qa_drain u_drain (
    .clk, .rst_n, .start(conv_start), .mode(f_mode), .cout64(f_cout64), .lho(f_lho), .lwo(f_lwo),
    .out_lay(f_out_lay), .res_lay(f_res_lay), .out_base(f_out_base), .res_base(f_res_base), .pbase(f_pbase),
    .cap(s3_vld && s3_last), .cap_ok, .shift, .heads_a, .heads_b, .pm_ce(dm_ce), .pm_addr(dm_addr), .pm_rdata(p_rdata),
    .q_vld, .q_acc, .q_bias, .q_m0, .q_sh, .q_d, .q_obank, .q_obank_hi, .q_rbank, .q_rbank_hi, .q_oaddr,
    .q_oaddr_hi, .q_raddr, .q_raddr_hi, .ppu_busy(|u_busy), .done(conv_done), .loading(ev_pload));

  // head
  logic [NBANK-1:0] hh_ce;
  logic [NBANK*AAW-1:0] hh_addr;
  logic hw2_ce, hp2_ce, hppu_vld, hres_vld;
  logic [WAW-1:0] hw2_addr;
  logic [PAW-1:0] hp2_addr;
  logic [8*ACC-1:0] hppu_acc;
  logic [63:0] hres;
  qa_head u_head (
    .clk, .rst_n, .start(head_start), .lhw(f_lhi + f_lwi), .in_base(f_in_base), .cin8(f_cin8),
    .ncls(f_cout64), .wbase(f_wbase), .pbase(f_pbase), .ar_ce(hh_ce), .ar_addr(hh_addr), .ar_rdata,
    .wm_ce(hw2_ce), .wm_addr(hw2_addr), .wm_rdata(we_rdata), .pm_ce(hp2_ce), .pm_addr(hp2_addr),
    .pm_rdata(p_rdata), .ppu_vld(hppu_vld), .ppu_acc(hppu_acc), .hp_vld(hres_vld), .hp(hres), .logits,
    .done(head_done));

  // two PPU units: unit 0 = drain chain A pixel (and the head pool), unit 1 = chain B pixel
  logic [1:0] u_pw_we, u_pr_re;
  logic [2*LNB-1:0] u_pw_bank, u_pr_bank;
  logic [2*AAW-1:0] u_pw_addr, u_pr_addr;
  logic [2*128-1:0] u_pw_wdata;
  logic [NPPU-1:0] u_hvld;
  logic [NPPU*64-1:0] u_hp;
  genvar u;
  for (u = 0; u < NPPU; u++) begin : g_ppu
    logic h;
    assign h = head_active && u == 0;
    qa_ppu u_ppu (
      .clk, .rst_n, .mode(f_mode), .head(h), .idm0(f_m0), .idsh(f_sh),
      .in_vld(head_active ? (u == 0 && hppu_vld) : q_vld),
      .in_acc(h ? {(8*ACC)'(0), hppu_acc} : q_acc[u*NL*ACC +: NL*ACC]),
      .in_bias(h ? '0 : q_bias),
      .in_m0(h ? {NL{f_m0}} : q_m0),
      .in_sh(h ? {NL{f_sh}} : q_sh),
      .in_d(h ? '0 : q_d),
      .in_obank(q_obank[u*LNB +: LNB]), .in_obank_hi(q_obank_hi[u*LNB +: LNB]),
      .in_rbank(q_rbank[u*LNB +: LNB]), .in_rbank_hi(q_rbank_hi[u*LNB +: LNB]),
      .in_oaddr(q_oaddr[u*AAW +: AAW]), .in_oaddr_hi(q_oaddr_hi[u*AAW +: AAW]),
      .in_raddr(q_raddr[u*AAW +: AAW]), .in_raddr_hi(q_raddr_hi[u*AAW +: AAW]),
      .pw_we(u_pw_we[u]), .pw_bank(u_pw_bank[u*LNB +: LNB]), .pw_addr(u_pw_addr[u*AAW +: AAW]),
      .pw_wdata(u_pw_wdata[u*128 +: 128]), .pr_re(u_pr_re[u]), .pr_bank(u_pr_bank[u*LNB +: LNB]),
      .pr_addr(u_pr_addr[u*AAW +: AAW]), .pr_rdata(pr_rdata[u*128 +: 128]),
      .h_vld(u_hvld[u]), .h_p(u_hp[u*64 +: 64]), .busy(u_busy[u]));
  end
  assign hres_vld = u_hvld[0];                       // head pool result (unit 0); unit 1 never runs in head mode
  assign hres     = u_hp[63:0];

  // ---- memories ------------------------------------------------------------------------------------------------
  // act buffers: port 0 of the residual reader / writer is shared with the host (idle only)
  wire h_rd = !busy && ha_ce && !ha_we, h_wr = !busy && ha_ce && ha_we;
  qa_actmem4 u_act (
    .clk, .rst_n, .ar_buf(f_in_buf), .ar_ce(head_active ? hh_ce : ag_ce), .ar_addr(head_active ? hh_addr : ag_addr),
    .ar_rdata,
    .pr_re({u_pr_re[1], busy ? u_pr_re[0] : h_rd}), .pr_buf(busy ? f_res_buf : ha_buf),
    .pr_bank({u_pr_bank[LNB +: LNB], busy ? u_pr_bank[0 +: LNB] : ha_bank}),
    .pr_addr({u_pr_addr[AAW +: AAW], busy ? u_pr_addr[0 +: AAW] : ha_addr}), .pr_rdata,
    .pw_we({u_pw_we[1], busy ? u_pw_we[0] : h_wr}), .pw_buf(busy ? f_out_buf : ha_buf),
    .pw_bank({u_pw_bank[LNB +: LNB], busy ? u_pw_bank[0 +: LNB] : ha_bank}),
    .pw_addr({u_pw_addr[AAW +: AAW], busy ? u_pw_addr[0 +: AAW] : ha_addr}),
    .pw_hm({2'b11, busy ? 2'b11 : (ha_half ? 2'b10 : 2'b01)}),
    .pw_wdata({u_pw_wdata[128 +: 128], busy ? u_pw_wdata[0 +: 128] : {ha_wdata, ha_wdata}}));

  // weight halves: even (input group 2j; FC words for the head), odd (group 2j + 1), same step address
  wire [WAW-1:0] w_addr = busy ? (head_active ? hw2_addr : s2_waddr) : hw_addr;
  qa_bankmem4 #(.BANKS(WBANKS), .BANK_WORDS(WBANK_WORDS), .BITS(WBITS), .AW(WAW)) u_wmem_e (
    .clk, .rst_n, .ce(busy ? (head_active ? hw2_ce : s2_wvld) : hw_ce && !hw_half), .we(!busy && hw_we),
    .addr(w_addr), .wdata(hw_wdata), .rdata(we_rdata));
  qa_bankmem4 #(.BANKS(WBANKS), .BANK_WORDS(WBANK_WORDS), .BITS(WBITS), .AW(WAW)) u_wmem_o (
    .clk, .rst_n, .ce(busy ? (!head_active && s2_wvld) : hw_ce && hw_half), .we(!busy && hw_we),
    .addr(w_addr), .wdata(hw_wdata), .rdata(wo_rdata));

  qa_bankmem4 #(.BANKS(PBANKS), .BANK_WORDS(PBANK_WORDS), .BITS(PBITS), .AW(PAW)) u_pmem (
    .clk, .rst_n, .ce(busy ? (head_active ? hp2_ce : dm_ce) : hp_ce), .we(!busy && hp_we),
    .addr(busy ? (head_active ? hp2_addr : dm_addr) : hp_addr), .wdata(hp_wdata), .rdata(p_rdata));

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n && busy && !head_active && |ag_ce &&
                            (f_in_buf == f_out_buf && |u_pw_we || f_in_buf == f_res_buf && |u_pr_re))
    $error("qa_top: array reads the buffer the PPU accesses");
`endif
endmodule
