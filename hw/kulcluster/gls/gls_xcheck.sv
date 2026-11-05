// X check on the gate-level KUL cluster's AXI interface, bound into chimera's RTL
// chimera_cluster_kulcluster (struct field names exist only on the RTL side of the wrapper).
// From the 4th clock after the cluster reset is released, every handshake bit driven by the
// netlist must be 0/1, and so must the address of a valid AW/AR and the data of a valid R.
// A violation is a $error (GLS_X ...), so the run fails instead of silently propagating X.
module gls_xcheck (
  input logic        clk_i,
  input logic        rst_ni,
  input logic [14:0] hs,       // handshakes driven by the cluster
  input logic        n_aw_v, n_ar_v, s_r_v, w_aw_v, w_ar_v,
  input logic [47:0] n_aw_a, n_ar_a, w_aw_a, w_ar_a,
  input logic [63:0] s_r_d
);
  int unsigned ncyc = 0, nerr = 0, nchk = 0;   // nchk: clock cycles checked (read by gls_probe.tcl)
  // debug: +GLS_HSLOG=<n> prints the first n changes of the handshake vector (zd vs sdf diff)
  int unsigned hslog = 0, nhs = 0;
  initial void'($value$plusargs("GLS_HSLOG=%d", hslog));
  always @(hs) if (rst_ni && nhs < hslog) begin nhs++; $display("GLS_HS %t %b", $time, hs); end
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) ncyc <= 0;
    else if (ncyc < 4) begin
      ncyc <= ncyc + 1;
      if (ncyc == 3 && nchk == 0) $display("GLS_XCHECK armed at %t", $time);
    end else if (nerr < 20) begin
      nchk++;
      if ($isunknown(hs))                    begin nerr++; $error("GLS_X handshake %b", hs); end
      if (n_aw_v === 1'b1 && $isunknown(n_aw_a)) begin nerr++; $error("GLS_X narrow aw.addr %h", n_aw_a); end
      if (n_ar_v === 1'b1 && $isunknown(n_ar_a)) begin nerr++; $error("GLS_X narrow ar.addr %h", n_ar_a); end
      if (w_aw_v === 1'b1 && $isunknown(w_aw_a)) begin nerr++; $error("GLS_X wide aw.addr %h", w_aw_a); end
      if (w_ar_v === 1'b1 && $isunknown(w_ar_a)) begin nerr++; $error("GLS_X wide ar.addr %h", w_ar_a); end
      if (s_r_v === 1'b1 && $isunknown(s_r_d))   begin nerr++; $error("GLS_X narrow-in r.data %h", s_r_d); end
    end
  end
endmodule

// Bind holder, loaded as a second top level (vsim tb_chimera_soc gls_bind): a bind in a separate
// compilation unit is otherwise not picked up by vopt.
module gls_bind;
bind chimera_cluster_kulcluster gls_xcheck i_gls_xcheck (
  .clk_i  (clu_clk_i),
  .rst_ni (rst_ni),
  .hs     ({clu_axi_adapter_mst_req.aw_valid, clu_axi_adapter_mst_req.w_valid,
            clu_axi_adapter_mst_req.ar_valid, clu_axi_adapter_mst_req.b_ready,
            clu_axi_adapter_mst_req.r_ready,
            clu_axi_adapter_slv_resp.aw_ready, clu_axi_adapter_slv_resp.w_ready,
            clu_axi_adapter_slv_resp.ar_ready, clu_axi_adapter_slv_resp.b_valid,
            clu_axi_adapter_slv_resp.r_valid,
            clu_axi_wide_mst_req.aw_valid, clu_axi_wide_mst_req.w_valid,
            clu_axi_wide_mst_req.ar_valid, clu_axi_wide_mst_req.b_ready,
            clu_axi_wide_mst_req.r_ready}),
  .n_aw_v (clu_axi_adapter_mst_req.aw_valid), .n_aw_a (clu_axi_adapter_mst_req.aw.addr),
  .n_ar_v (clu_axi_adapter_mst_req.ar_valid), .n_ar_a (clu_axi_adapter_mst_req.ar.addr),
  .w_aw_v (clu_axi_wide_mst_req.aw_valid),    .w_aw_a (clu_axi_wide_mst_req.aw.addr),
  .w_ar_v (clu_axi_wide_mst_req.ar_valid),    .w_ar_a (clu_axi_wide_mst_req.ar.addr),
  .s_r_v  (clu_axi_adapter_slv_resp.r_valid), .s_r_d  (clu_axi_adapter_slv_resp.r.data)
);
endmodule
