#!/usr/bin/env bash
# Per-access energies of the R4 macros from the ARM datatables at tt_1p0v_25c (run on the build host; prints numbers
# only): rf_sp read = (icc_c_r0 + icc_p_r0) V, write = (icc_c_w0 + icc_p_w0) V; rf_2p read (port A) = icc_*_a0,
# write (port B) = icc_*_b0; mA/MHz x V x 1000 = pJ; standby = (icc_c_standby + icc_p_standby) x V (mW, per macro).
. "$(dirname "$0")/../../../flow/tsmc65/site/sram.sh"
for i in $(sed 's/#.*//' "$(dirname "$0")/macros.txt" | awk 'NF >= 5 {print $1}'); do
    awk -v i="$i" '$1 == "name" { for (k = 2; k <= NF; k++) if ($k == "tt_1p0v_25c") c = k; next }
        { v[$1] = $c }
        END { V = v["volt"];
              if ("icc_c_r0" in v) { r = v["icc_c_r0"] + v["icc_p_r0"]; w = v["icc_c_w0"] + v["icc_p_w0"]; d = v["icc_c_desel"] + v["icc_p_desel"] }
              else { r = v["icc_c_a0"] + v["icc_p_a0"]; w = v["icc_c_b0"] + v["icc_p_b0"]; d = v["icc_desel_c_a"] + v["icc_desel_p_a"] + v["icc_desel_c_b"] + v["icc_desel_p_b"] }
              printf "%s read_pJ %.3f write_pJ %.3f desel_pJ %.3f standby_mW %.4f\n", i, r * V * 1000, w * V * 1000, d * V * 1000, (v["icc_c_standby"] + v["icc_p_standby"]) * V }' \
        "$QC_MC_OUT/$i/$i.dat"
done
