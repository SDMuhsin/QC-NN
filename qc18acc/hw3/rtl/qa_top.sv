// QC18-ACC v3 (Kb = 2) top level (qc18acc/ARCH.md "v3"; v2 = hw/rtl/qa_top.sv).  Single clock, synchronous
// active-low reset.  v3: 128-b pair words (qa_actmem 3 x 8 x 2 x qa_sram 512 x 64), even / odd weight SRAM halves
// (2 x qa_bankmem 3 x 4096 x 80, same address), 8 x 8 array of 2-block PEs, 2-column drain, 16-lane PPU.
//   qa_host (host port, CSRs) -> qa_seq (descriptors, perf counters) -> per conv pass:
//     qa_agu (S0 -> S1) -> act buffers + weight SRAM (S1 -> S2) -> qa_xbar (S2 -> S3) -> qa_array (S3, 8 x 8 qa_pe)
//     -> shadow chains -> qa_drain (param RF, drain, addresses) -> qa_ppu (r1..r6) -> act buffer write
//   head: qa_head (pool via qa_ppu, FC) -> logits
// Memories: qa_actmem (3 x 8 x 2 x qa_sram 512 x 64), weight u_wmem_e / u_wmem_o (each qa_bankmem 3 x 4096 x 80),
// param qa_bankmem (2 x 4096 x 72), descriptor qa_sram 256 x 32.
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
  logic [2:0] ha_bank;
  logic [AAW-1:0] ha_addr;
  logic [63:0] ha_wdata, ha_rdata;

  qa_host u_host (
    .clk, .rst_n, .host_req, .host_we, .host_addr, .host_wdata, .host_rvalid, .host_rdata,
    .start, .busy, .done,
    .d_ce(hd_ce), .d_we(hd_we), .d_addr(hd_addr), .d_wdata(hd_wdata), .d_rdata(d_rdata),
    .p_ce(hp_ce), .p_we(hp_we), .p_addr(hp_addr), .p_wdata(hp_wdata), .p_rdata(p_rdata),
    .w_ce(hw_ce), .w_we(hw_we), .w_half(hw_half), .w_addr(hw_addr), .w_wdata(hw_wdata), .we_rdata, .wo_rdata,
    .a_ce(ha_ce), .a_we(ha_we), .a_buf(ha_buf), .a_bank(ha_bank), .a_half(ha_half), .a_addr(ha_addr), .a_wdata(ha_wdata),
    .a_rdata(ha_rdata),
    .cyc_total, .cyc_busy, .cyc_stall, .cyc_pload, .cnt_ard, .npass, .cyc_pass, .logits);

  // ---- sequencer + descriptor RAM ------------------------------------------------------------------------------
  logic sd_ce;
  logic [DAW-1:0] sd_addr;
  logic ev_busy, ev_stall, ev_pload;
  logic [3:0] ev_ard;
  qa_seq u_seq (
    .clk, .rst_n, .start, .busy, .done, .d_ce(sd_ce), .d_addr(sd_addr), .d_rdata(d_rdata),
    .f_k, .f_stride, .f_mode, .f_in_lay, .f_out_lay, .f_res_lay, .f_in_buf, .f_out_buf, .f_res_buf,
    .f_hin, .f_win, .f_hout, .f_wout, .f_lhi, .f_lwi, .f_lho, .f_lwo, .f_cin8, .f_cout64,
    .f_in_base, .f_out_base, .f_res_base, .f_wbase, .f_pbase, .f_m0, .f_sh,
    .conv_start, .conv_done, .head_start, .head_done, .head_active, .pass_done, .pass_idx,
    .ev_busy, .ev_stall, .ev_pload, .ev_ard, .cyc_total, .cyc_busy, .cyc_stall, .cyc_pload, .cnt_ard, .npass,
    .cyc_pass);
  qa_sram #(.WORDS(DWORDS), .BITS(32)) u_desc (
    .clk, .ce(busy ? sd_ce : hd_ce), .we(!busy && hd_we), .addr(busy ? sd_addr : hd_addr), .wdata(hd_wdata),
    .rdata(d_rdata));

  // ---- array path ----------------------------------------------------------------------------------------------
  logic cap_ok, agu_done, s1_vld, s1_first, s1_last;
  logic [NBANK-1:0] s1_ce;
  logic [NBANK*AAW-1:0] s1_addr;
  logic [2:0] s1_rot;
  logic [7:0] s1_lane, s1_rd;
  logic s1_shift;
  logic [WAW-1:0] s1_waddr;
  qa_agu u_agu (
    .clk, .rst_n, .start(conv_start), .k(f_k), .stride(f_stride), .lhi(f_lhi), .lwi(f_lwi), .lho(f_lho),
    .lwo(f_lwo), .hin(f_hin), .win(f_win), .cin8(f_cin8), .cout64(f_cout64), .in_base(f_in_base),
    .wbase(f_wbase), .cap_ok, .done(agu_done), .stall(ev_stall), .s1_vld, .s1_first, .s1_last, .s1_ce,
    .s1_addr, .s1_rot, .s1_lane, .s1_rd, .s1_shift, .s1_waddr);
  always_comb begin                                  // array act-bank reads this cycle (perf counter CSR_ACT_RD)
    ev_ard = '0;
    for (int b = 0; b < NBANK; b++) ev_ard = ev_ard + 4'(s1_ce[b]);
  end

  logic [NBANK*128-1:0] ar_rdata;
  logic s3_vld, s3_first, s3_last;
  logic [8*128-1:0] s3_x;
  logic [8*20-1:0] s3_code;
  qa_xbar u_xbar (
    .clk, .rst_n, .s1_vld, .s1_first, .s1_last, .s1_rot, .s1_lane, .s1_rd, .s1_shift, .ar_rdata, .we_rdata, .wo_rdata, .s3_vld, .s3_first,
    .s3_last, .s3_x, .s3_code);
  assign ev_busy = s3_vld;

  logic [7:0] shift;
  logic [8*8*ACC-1:0] heads;
  qa_array u_array (
    .clk, .vld(s3_vld), .first(s3_first), .last(s3_last), .x(s3_x), .code(s3_code), .shift, .heads);

  // ---- drain + PPU ---------------------------------------------------------------------------------------------
  logic dm_ce;
  logic [PAW-1:0] dm_addr;
  logic q_vld;
  logic [NL*ACC-1:0] q_acc;
  logic [NL*VW-1:0] q_bias;
  logic [NL*31-1:0] q_m0;
  logic [NL*6-1:0] q_sh;
  logic [NL-1:0] q_d;
  logic [2:0] q_obank, q_obank_hi, q_rbank, q_rbank_hi;
  logic [AAW-1:0] q_oaddr, q_oaddr_hi, q_raddr, q_raddr_hi;
  logic ppu_busy;
  qa_drain u_drain (
    .clk, .rst_n, .start(conv_start), .mode(f_mode), .cout64(f_cout64), .lho(f_lho), .lwo(f_lwo),
    .out_lay(f_out_lay), .res_lay(f_res_lay), .out_base(f_out_base), .res_base(f_res_base), .pbase(f_pbase),
    .cap(s3_vld && s3_last), .cap_ok, .shift, .heads, .pm_ce(dm_ce), .pm_addr(dm_addr), .pm_rdata(p_rdata),
    .q_vld, .q_acc, .q_bias, .q_m0, .q_sh, .q_d, .q_obank, .q_obank_hi, .q_rbank, .q_rbank_hi, .q_oaddr,
    .q_oaddr_hi, .q_raddr, .q_raddr_hi, .ppu_busy, .done(conv_done), .loading(ev_pload));

  // head
  logic [NBANK-1:0] hh_ce_lo, hh_ce_hi;
  logic [NBANK*AAW-1:0] hh_addr;
  logic hw2_ce, hp2_ce, hppu_vld, hres_vld;
  logic [WAW-1:0] hw2_addr;
  logic [PAW-1:0] hp2_addr;
  logic [8*ACC-1:0] hppu_acc;
  logic [63:0] hres;
  qa_head u_head (
    .clk, .rst_n, .start(head_start), .lhw(f_lhi + f_lwi), .in_base(f_in_base), .cin8(f_cin8),
    .ncls(f_cout64), .wbase(f_wbase), .pbase(f_pbase), .ar_ce_lo(hh_ce_lo), .ar_ce_hi(hh_ce_hi), .ar_addr(hh_addr),
    .ar_rdata, .wm_ce(hw2_ce), .wm_addr(hw2_addr), .wm_rdata(we_rdata), .pm_ce(hp2_ce), .pm_addr(hp2_addr),
    .pm_rdata(p_rdata), .ppu_vld(hppu_vld), .ppu_acc(hppu_acc), .hp_vld(hres_vld), .hp(hres), .logits,
    .done(head_done));

  logic pw_we, pr_re;
  logic [1:0] pw_buf, pr_buf;
  logic [2:0] pw_bank, pr_bank;
  logic [AAW-1:0] pw_addr, pr_addr;
  logic [127:0] pw_wdata, pr_rdata;
  qa_ppu u_ppu (
    .clk, .rst_n, .mode(f_mode), .head(head_active), .out_buf(f_out_buf), .res_buf(f_res_buf), .idm0(f_m0),
    .idsh(f_sh),
    .in_vld(head_active ? hppu_vld : q_vld),
    .in_acc(head_active ? {(8*ACC)'(0), hppu_acc} : q_acc),
    .in_bias(head_active ? '0 : q_bias),
    .in_m0(head_active ? {NL{f_m0}} : q_m0),
    .in_sh(head_active ? {NL{f_sh}} : q_sh),
    .in_d(head_active ? '0 : q_d),
    .in_obank(q_obank), .in_obank_hi(q_obank_hi), .in_rbank(q_rbank), .in_rbank_hi(q_rbank_hi),
    .in_oaddr(q_oaddr), .in_oaddr_hi(q_oaddr_hi), .in_raddr(q_raddr), .in_raddr_hi(q_raddr_hi),
    .pw_we, .pw_buf, .pw_bank, .pw_addr, .pw_wdata, .pr_re, .pr_buf, .pr_bank, .pr_addr, .pr_rdata,
    .h_vld(hres_vld), .h_p(hres), .busy(ppu_busy));

  // ---- memories ------------------------------------------------------------------------------------------------
  qa_actmem u_act (
    .clk, .ar_buf(f_in_buf), .ar_ce_lo(head_active ? hh_ce_lo : s1_ce), .ar_ce_hi(head_active ? hh_ce_hi : s1_ce),
    .ar_addr(head_active ? hh_addr : s1_addr),
    .ar_rdata, .pw_we, .pw_buf, .pw_bank, .pw_addr, .pw_wdata, .pr_re, .pr_buf, .pr_bank, .pr_addr, .pr_rdata,
    .h_ce(!busy && ha_ce), .h_we(ha_we), .h_buf(ha_buf), .h_bank(ha_bank), .h_half(ha_half), .h_addr(ha_addr),
    .h_wdata(ha_wdata),
    .h_rdata(ha_rdata));

  // weight halves: even (input group 2j; FC words for the head), odd (group 2j + 1), same step address
  wire [WAW-1:0] w_addr = busy ? (head_active ? hw2_addr : s1_waddr) : hw_addr;
  qa_bankmem #(.BANKS(WBANKS), .BANK_WORDS(WBANK_WORDS), .BITS(WBITS), .AW(WAW)) u_wmem_e (
    .clk, .ce(busy ? (head_active ? hw2_ce : s1_vld) : hw_ce && !hw_half), .we(!busy && hw_we),
    .addr(w_addr), .wdata(hw_wdata), .rdata(we_rdata));
  qa_bankmem #(.BANKS(WBANKS), .BANK_WORDS(WBANK_WORDS), .BITS(WBITS), .AW(WAW)) u_wmem_o (
    .clk, .ce(busy ? (!head_active && s1_vld) : hw_ce && hw_half), .we(!busy && hw_we),
    .addr(w_addr), .wdata(hw_wdata), .rdata(wo_rdata));

  qa_bankmem #(.BANKS(PBANKS), .BANK_WORDS(PBANK_WORDS), .BITS(PBITS), .AW(PAW)) u_pmem (
    .clk, .ce(busy ? (head_active ? hp2_ce : dm_ce) : hp_ce), .we(!busy && hp_we),
    .addr(busy ? (head_active ? hp2_addr : dm_addr) : hp_addr), .wdata(hp_wdata), .rdata(p_rdata));

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n && busy && !head_active && |s1_ce &&
                            (f_in_buf == pw_buf && pw_we || f_in_buf == pr_buf && pr_re))
    $error("qa_top: array reads the buffer the PPU accesses");
`endif
endmodule
