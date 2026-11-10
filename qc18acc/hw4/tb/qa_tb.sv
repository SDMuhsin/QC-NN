// QC18-ACC v4 (16 pixel rows) full-network testbench: v3 hw3/tb/qa_tb.sv with the v4 memory images (python3 -m
// qc18acc.compile4.main --export): 16 banks x 256 words per buffer (host act address [12:9] bank, [8:1] address,
// [0] half), output buffers of 4096 x 128 b with line = bank * 256 + address.
// QC18-ACC full-network testbench.
//   +DIR=<export dir>  (python3 -m qc18acc.compile.main --export DIR --images ...)   +IMG0=<first image id>
//   +NIMG=<number of images> (DIR/names.txt = pass names of DIR/program.txt, one per line, written by run_rtl.sh)
//     +MAXCYC=<per-image cycle limit>   +NOMAPS (logits only)   +SAIF=<file> (with +define+QA_SAIF)
// Loading: EVERYTHING through the host port (descriptors, weight / param SRAM words with the WSTAGE registers,
// then per image the 1024-word input plane into the stem's input buffer).  Per image: START, poll STATUS, read
// the 10 logits and the perf counters through the host port.
// Map check: at the end of every conv pass (u_seq.npass incremented) the pass's output buffer is copied by
// hierarchical reference (backdoor, read-only, at the next clock edge, before any write of the next pass) and compared word by word with
// DIR/img<n>/pass<ii>_<name>.hex (words marked x are not written by the pass and are skipped).
`timescale 1ns/1ps
module qa_tb;
  import qa_pkg::*;
  logic clk = 1'b0, rst_n = 1'b0;
  always #1.25 clk = ~clk;                                     // 2.5 ns
  longint cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  logic host_req = 1'b0, host_we = 1'b0, host_rvalid, busy, done;
  logic [23:0] host_addr = '0;
  logic [31:0] host_wdata = '0, host_rdata;
  qa_top dut (.clk, .rst_n, .host_req, .host_we, .host_addr, .host_wdata, .host_rvalid, .host_rdata, .busy, .done);

  reg [8*512-1:0] dir;
  reg [8*64-1:0]  pname [0:MAXPASS-1];
  integer img0, nimg, maxcyc, nomaps, errors, map_err, npass_conv, nw, np, nd, cur_img, chk_k;
  logic [WBITS-1:0] wimg [0:WBANKS*WBANK_WORDS-1];
  logic [WBITS-1:0] oimg [0:WBANKS*WBANK_WORDS-1];
  logic [PBITS-1:0] pimg [0:PBANKS*PBANK_WORDS-1];
  logic [31:0] dimg [0:DWORDS-1];
  logic [127:0] inimg [0:1023];
  logic [127:0] expw [0:4095];
  logic [31:0] lexp [0:MAXCLS-1];
  logic [127:0] snap [0:NBUF*4096-1];
  integer no;

  // ---- host port tasks -----------------------------------------------------------------------------------------
  task automatic hwr(input logic [23:0] a, input logic [31:0] d);
    host_req <= 1'b1; host_we <= 1'b1; host_addr <= a; host_wdata <= d;
    @(posedge clk);
    host_req <= 1'b0; host_we <= 1'b0;
  endtask
  task automatic hrd(input logic [23:0] a, output logic [31:0] d);
    host_req <= 1'b1; host_we <= 1'b0; host_addr <= a;
    @(posedge clk);
    host_req <= 1'b0;
    do @(posedge clk); while (host_rvalid !== 1'b1);
    d = host_rdata;
  endtask

  // ---- backdoor snapshot of the act buffers at a pass end ------------------------------------------------------
  // Memory view: RTL qa_sram (mem[a]); +define+QA_TECH: hw/tech/qa_sram_tech.sv on the ARM macro model
  // qa_act_1024x64m8 (column mux 8: word a in row a >> 3, bit b at 8 b + a % 8); +define+QA_GLS: the netlist, whose
  // escaped instance names come from the generated include qa_gls_snap.svh (qc18acc/gls/gen_snap.py).
  logic snap_go = 1'b0, pass_end_q = 1'b0;
  function automatic logic [63:0] unmux4(input logic [255:0] row, input int m);
    for (int b = 0; b < 64; b++) unmux4[b] = row[4*b + m];
  endfunction
`ifdef QA_GLS
  `include "qa_gls_snap.svh"
`else
  // v4 memory view: RTL qa_sram4 (mem[a], 128 b); QA_TECH: hw4/tech/qa_sram4_tech.sv on the ARM model
  // qa_act_256x128m2 (rf_sp_adv column mux 2: word a in row a >> 1, bit b at 2 b + a % 2); QA_GLS: generated include
  function automatic logic [127:0] unmux2(input logic [255:0] row, input int m);
    for (int b = 0; b < 128; b++) unmux2[b] = row[2*b + m];
  endfunction
  genvar gb, gk;
  for (gb = 0; gb < NBUF; gb++) begin : g_sb
    for (gk = 0; gk < NBANK; gk++) begin : g_sk
      always @(posedge clk) if (snap_go) for (int a = 0; a < ADEPTH; a++)
`ifdef QA_TECH
        snap[gb*4096 + gk*256 + a] = unmux2(dut.u_act.g_bank[gk].g_buf[gb].u_ram.g_mac.g_act.u_mac.mem[a >> 1], a % 2);
`else
        snap[gb*4096 + gk*256 + a] = dut.u_act.g_bank[gk].g_buf[gb].u_ram.mem[a];
`endif
    end
  end
`endif
  // pass end: the cycle u_seq.pass_done is high = the cycle after u_seq.npass was incremented (the netlist has no
  // pass_done: it has no load in qa_top and synthesis removes it; npass feeds the host CSRs)
  // (flat P&R netlists: the generated include defines QA_NPASS as the Q nets of the u_seq/npass registers)
`ifndef QA_NPASS
  `define QA_NPASS dut.u_seq.npass
`endif
  logic [5:0] npass_q = '0;
  wire pass_end = `QA_NPASS !== npass_q && `QA_NPASS != 6'd0;
  always @(negedge clk) begin
    snap_go <= rst_n && pass_end && chk_k < npass_conv && nomaps == 0;
    pass_end_q <= rst_n && pass_end;
    npass_q <= `QA_NPASS;
  end
  always @(posedge clk) if (snap_go) begin
    reg [8*600-1:0] fn;
    integer bad, cnt, ob;
    #0.5;                                                       // after the copy blocks of this edge
    ob = dimg[8*chk_k][14:13];
    $sformat(fn, "%0s/img%0d/pass%02d_%0s.hex", dir, cur_img, chk_k, pname[chk_k]);
    for (int i = 0; i < 4096; i++) expw[i] = 'x;
    $readmemh(fn, expw);
    bad = 0; cnt = 0;
    for (int i = 0; i < 4096; i++) if (expw[i][0] !== 1'bx) begin
      cnt = cnt + 1;
      if (snap[ob*4096 + i] !== expw[i]) begin
        if (bad < 5) $display("  MISMATCH img %0d pass %0d %0s buf %0d bank %0d addr %0d: got %h exp %h", cur_img,
                              chk_k, pname[chk_k], ob, i / 256, i % 256, snap[ob*4096 + i], expw[i]);
        bad = bad + 1;
      end
    end
    if (cnt == 0) begin $display("  MISMATCH: no expected words in %0s", fn); bad = 1; end
    map_err = map_err + bad;
    if (bad) $display("MAP img %0d pass %02d %-14s %0d words: %0d mismatches", cur_img, chk_k, pname[chk_k], cnt, bad);
    chk_k = chk_k + 1;
    $fflush();
  end else if (pass_end_q) chk_k = chk_k + 1;

`ifdef QA_SAIF
  // +define+QA_SAIF (VCS): toggle counts of the whole DUT over START..DONE of the first image -> SAIF +SAIF=<file>
  // (default qa_top.saif).  saif_st: 1 = started, waiting for done low (still high from a previous image), 2 = running.
  integer saif_st = 0;
  longint saif_c0;
  string saif_fn;
  task automatic saif_start;
    if (!$value$plusargs("SAIF=%s", saif_fn)) saif_fn = "qa_top.saif";
    $set_gate_level_monitoring("on");
    $set_toggle_region(qa_tb.dut);
    $toggle_start;
    saif_st = 1; saif_c0 = cyc;
  endtask
  always @(posedge clk) begin
    if (saif_st == 1 && done === 1'b0) saif_st = 2;
    else if (saif_st == 2 && done === 1'b1) begin
      $toggle_stop;
      $toggle_report(saif_fn, 1.0e-9, "qa_tb.dut");
      $display("SAIF %0s: cycles %0d..%0d (%0d)", saif_fn, saif_c0, cyc, cyc - saif_c0);
      saif_st = 3;
    end
  end
`endif

  // ---- main ----------------------------------------------------------------------------------------------------
  initial begin
    integer fd, r, n, img_buf, img_base;
    reg [8*256-1:0] line;
    reg [8*64-1:0] nm;
    reg [8*600-1:0] fn;
    logic [31:0] v, st, tot, bsy, stl, pld, npa, ard;
    logic [31:0] pc [0:MAXPASS-1];
    integer lerr, ncv_cyc;
    if (!$value$plusargs("DIR=%s", dir)) begin $display("FAIL: need +DIR=<export dir>"); $finish; end
    if (!$value$plusargs("IMG0=%d", img0)) img0 = 0;
    if (!$value$plusargs("NIMG=%d", nimg)) nimg = 1;
    if (!$value$plusargs("MAXCYC=%d", maxcyc)) maxcyc = 400000;
    nomaps = $test$plusargs("NOMAPS") ? 1 : 0;
    errors = 0; map_err = 0; chk_k = 0;
    for (int i = 0; i < WBANKS*WBANK_WORDS; i++) begin wimg[i] = 'x; oimg[i] = 'x; end
    for (int i = 0; i < PBANKS*PBANK_WORDS; i++) pimg[i] = 'x;
    for (int i = 0; i < DWORDS; i++) dimg[i] = 'x;
    $sformat(fn, "%0s/weights_e.hex", dir); $readmemh(fn, wimg);
    $sformat(fn, "%0s/weights_o.hex", dir); $readmemh(fn, oimg);
    $sformat(fn, "%0s/params.hex", dir);  $readmemh(fn, pimg);
    $sformat(fn, "%0s/desc.hex", dir);    $readmemh(fn, dimg);
    nw = 0; while (nw < WBANKS*WBANK_WORDS && wimg[nw][0] !== 1'bx) nw = nw + 1;
    no = 0; while (no < WBANKS*WBANK_WORDS && oimg[no][0] !== 1'bx) no = no + 1;
    np = 0; while (np < PBANKS*PBANK_WORDS && pimg[np][0] !== 1'bx) np = np + 1;
    nd = 0; while (dimg[nd][17] !== 1'b1) nd = nd + 8;
    nd = nd + 8;
    npass_conv = nd / 8 - 1;
    img_buf = dimg[0][12:11]; img_base = dimg[3][9:0];
    $sformat(fn, "%0s/names.txt", dir);                       // pass names, one per line (run_rtl.sh, from program.txt)
    fd = $fopen(fn, "r");
    if (fd == 0) begin $display("FAIL: cannot open %0s", fn); $finish; end
    n = 0;
    while (n < MAXPASS && $fscanf(fd, "%s", nm) == 1) begin pname[n] = nm; n = n + 1; end
    $fclose(fd);
    $display("TB: v4, dir %0s, %0d + %0d (odd) weight words, %0d param words, %0d descriptor words (%0d conv passes + head), images %0d..%0d",
             dir, nw, no, np, nd, npass_conv, img0, img0 + nimg - 1);
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    repeat (2) @(posedge clk);
    // ---- program load through the host port ----
    for (int i = 0; i < nd; i++) hwr(24'h001000 + i, dimg[i]);
    for (int i = 0; i < nw; i++) begin
      hwr(CSR_WSTAGE2, 32'(wimg[i][79:64])); hwr(CSR_WSTAGE1, wimg[i][63:32]); hwr({R_WEIGHT, 20'(i)}, wimg[i][31:0]);
    end
    for (int i = 0; i < no; i++) begin
      hwr(CSR_WSTAGE2, 32'(oimg[i][79:64])); hwr(CSR_WSTAGE1, oimg[i][63:32]); hwr({R_WEIGHT, 20'(i) | 20'h4000}, oimg[i][31:0]);
    end
    for (int i = 0; i < np; i++) begin
      hwr(CSR_WSTAGE2, 32'(pimg[i][71:64])); hwr(CSR_WSTAGE1, pimg[i][63:32]); hwr({R_PARAM, 20'(i)}, pimg[i][31:0]);
    end
    // spot read-back of the loaded images
    for (int i = 0; i < nw; i += 997) begin
      hrd({R_WEIGHT, 20'(i)}, v); hrd(CSR_RSTAGE1, tot); hrd(CSR_RSTAGE2, bsy);
      if ({bsy[15:0], tot, v} !== wimg[i]) begin $display("FAIL: weight read-back %0d", i); errors = errors + 1; end
    end
    for (int i = 0; i < no; i += 997) begin
      hrd({R_WEIGHT, 20'(i) | 20'h4000}, v); hrd(CSR_RSTAGE1, tot); hrd(CSR_RSTAGE2, bsy);
      if ({bsy[15:0], tot, v} !== oimg[i]) begin $display("FAIL: odd weight read-back %0d", i); errors = errors + 1; end
    end
    hrd(24'h001000, v); if (v !== dimg[0]) begin $display("FAIL: descriptor read-back"); errors = errors + 1; end
    $display("TB: program loaded through the host port at cycle %0d", cyc);
    $fflush();

    for (int im = img0; im < img0 + nimg; im++) begin
      cur_img = im; chk_k = 0;
      for (int i = 0; i < 1024; i++) inimg[i] = 'x;
      $sformat(fn, "%0s/img%0d/input.hex", dir, im); $readmemh(fn, inimg);
      for (int i = 0; i < 1024 && inimg[i][0] !== 1'bx; i++) begin
        hwr(CSR_WSTAGE1, inimg[i][63:32]);
        hwr({R_ACT, 5'd0, 2'(img_buf), 4'(i % 16), 8'(img_base + i / 16), 1'b0}, inimg[i][31:0]);
        hwr(CSR_WSTAGE1, inimg[i][127:96]);
        hwr({R_ACT, 5'd0, 2'(img_buf), 4'(i % 16), 8'(img_base + i / 16), 1'b1}, inimg[i][95:64]);
      end
      hwr(CSR_CTRL, 32'd1);
`ifdef QA_SAIF
      if (im == img0) saif_start();
`endif
      st = 0; n = 0;
      while (!st[1]) begin
        repeat (256) @(posedge clk);
        n = n + 256;
        hrd(CSR_STATUS, st);
        if (n > maxcyc) begin $display("FAIL: image %0d timeout after %0d cycles", im, n); $finish; end
      end
      // logits
      $sformat(fn, "%0s/img%0d/logits.hex", dir, im); $readmemh(fn, lexp);
      lerr = 0;
      for (int j = 0; j < 10; j++) begin
        hrd(CSR_LOGIT0 + j, v);
        if (v !== lexp[j]) begin
          $display("  LOGIT MISMATCH img %0d j %0d got %0d exp %0d", im, j, $signed(v), $signed(lexp[j]));
          lerr = lerr + 1;
        end
      end
      // perf counters
      hrd(CSR_CYC_TOTAL, tot); hrd(CSR_CYC_BUSY, bsy); hrd(CSR_CYC_STALL, stl); hrd(CSR_CYC_PLOAD, pld); hrd(CSR_ACT_RD, ard);
      hrd(CSR_NPASS, npa);
      for (int i = 0; i < npa; i++) hrd(CSR_PASS0 + i, pc[i]);
      for (int i = 0; i < npa; i++)
        $display("PASSCYC img %0d pass %02d %-14s %0d", im, i, i < npass_conv ? pname[i] : "head", pc[i]);
      $display("PERF img %0d total %0d array_busy %0d (%.1f %%) stall %0d param_load %0d passes %0d act_reads %0d", im,
               tot, bsy, 100.0 * bsy / tot, stl, pld, npa, ard);
      if (chk_k != npass_conv + 1) begin $display("  saw %0d pass ends, expected %0d", chk_k, npass_conv + 1); lerr = lerr + 1; end
      $display("IMAGE %0d: logits %0s, maps %0s (%0d passes checked)", im, lerr ? "MISMATCH" : "exact",
               nomaps ? "not checked" : (map_err ? "MISMATCH" : "exact"), nomaps ? 0 : npass_conv);
      errors = errors + lerr;
      $fflush();
    end
    errors = errors + map_err;
    if (errors == 0) $display("RESULT PASS: %0d images, all logits%0s bit-exact", nimg, nomaps ? "" : " and all stored maps");
    else $display("RESULT FAIL: %0d errors", errors);
    $finish;
  end
endmodule
