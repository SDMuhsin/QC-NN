// Verilator testbench of the QC RescaleSIMD with the per-output-channel requant table
// (snax_acc.qcgemm.QcPipelinedRescaleSIMD) against qcacc.model.requant + nn.quant.hw.simd_rescale,
// vectors from qcacc/hw/tb/vectors_simd.py.
//   Vtb_simd <vectors.txt> [stall_percent] [which: 1 input valid, 2 output ready, 3 both]
// Every other case randomly withholds input valid and/or output ready.  Exit 0 = every output bit-exact.
// Note: with output-ready stalls (2, 3) the upstream PipelinedRescaleSIMD itself fails (also with the
// table disabled): its lane-valid counter shifts output_data_reg without an output handshake.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "VQcPipelinedRescaleSIMD.h"
#include "verilated.h"

typedef std::vector<uint32_t> Bits;
static Bits parse_hex(const std::string &h) {
    size_t nb = h.size() / 2;
    Bits w((nb + 3) / 4, 0);
    for (size_t i = 0; i < nb; i++)
        w[i / 4] |= (uint32_t)std::strtoul(h.substr((nb - 1 - i) * 2, 2).c_str(), nullptr, 16) << (8 * (i % 4));
    return w;
}

struct Case {
    std::string name;
    uint32_t T = 0, ctrl[13] = {0}, map = 0;
    Bits mult, shift;
    std::vector<Bits> in, out;
};

static bool load(std::ifstream &f, Case &cs) {
    std::string line, tag;
    if (!std::getline(f, line)) return false;
    std::istringstream h(line);
    h >> tag;
    if (tag != "case") return false;
    h >> cs.name >> cs.T;
    std::getline(f, line);
    { std::istringstream s(line); s >> tag; for (int i = 0; i < 13; i++) { std::string x; s >> x; cs.ctrl[i] = std::strtoul(x.c_str(), nullptr, 16); } }
    std::getline(f, line);
    { std::istringstream s(line); std::string m, a, b; s >> tag >> m >> a >> b;
      cs.map = std::strtoul(m.c_str(), nullptr, 16); cs.mult = parse_hex(a); cs.shift = parse_hex(b); }
    for (uint32_t t = 0; t < cs.T; t++) {
        std::string x;
        std::getline(f, line); { std::istringstream s(line); s >> tag >> x; cs.in.push_back(parse_hex(x)); }
        std::getline(f, line); { std::istringstream s(line); s >> tag >> x; cs.out.push_back(parse_hex(x)); }
    }
    return true;
}

static VQcPipelinedRescaleSIMD *top;
static void tick() { top->clock = 1; top->eval(); top->clock = 0; top->eval(); }

int main(int argc, char **argv) {
    if (argc < 2) { std::fprintf(stderr, "usage: %s vectors.txt [stall_percent]\n", argv[0]); return 2; }
    int stall = argc > 2 ? std::atoi(argv[2]) : 0;
    int which = argc > 3 ? std::atoi(argv[3]) : 3;   // stall: 1 input valid, 2 output ready, 3 both
    Verilated::commandArgs(argc, argv);
    top = new VQcPipelinedRescaleSIMD;
    std::srand(3);
    top->clock = 0; top->reset = 1; top->eval();
    for (int i = 0; i < 4; i++) tick();
    top->reset = 0; top->eval();
    std::ifstream f(argv[1]);
    Case cs;
    long n_case = 0, bad_case = 0, bad_tiles = 0, tiles = 0, en_cases = 0, max_groups_seen = 0;
    while (load(f, cs)) {
        int st = (n_case % 2) ? stall : 0;
        auto rnd = [&]() { return st > 0 && (std::rand() % 100) < st; };
        top->qc_rq_map = cs.map;
        std::memcpy(top->qc_rq_mult.data(), cs.mult.data(), 256);
        std::memcpy(top->qc_rq_shift.data(), cs.shift.data(), 64);
        uint32_t *cb[13] = {&top->io_ctrl_bits_0, &top->io_ctrl_bits_1, &top->io_ctrl_bits_2, &top->io_ctrl_bits_3,
                            &top->io_ctrl_bits_4, &top->io_ctrl_bits_5, &top->io_ctrl_bits_6, &top->io_ctrl_bits_7,
                            &top->io_ctrl_bits_8, &top->io_ctrl_bits_9, &top->io_ctrl_bits_10, &top->io_ctrl_bits_11,
                            &top->io_ctrl_bits_12};
        for (int i = 0; i < 13; i++) *cb[i] = cs.ctrl[i];
        top->io_ctrl_valid = 1;
        top->io_data_input_i_valid = 0;
        top->io_data_output_o_ready = 0;
        top->eval();
        int guard = 0;
        while (!top->io_ctrl_ready && guard++ < 1000) tick();
        tick();
        top->io_ctrl_valid = 0;
        size_t ii = 0, io = 0;
        bool v = false;
        long case_bad = 0, cyc = 0, limit = 40L * cs.T + 200;
        while (io < cs.T && cyc++ < limit) {
            if (!v && ii < cs.T && !((which & 1) && rnd())) v = true;
            top->io_data_input_i_valid = v;
            if (v) std::memcpy(top->io_data_input_i_bits.data(), cs.in[ii].data(), 256);
            top->io_data_output_o_ready = !((which & 2) && rnd());
            top->eval();
            bool fi = v && top->io_data_input_i_ready;
            if (top->io_data_output_o_valid && top->io_data_output_o_ready) {
                if (std::memcmp(top->io_data_output_o_bits.data(), cs.out[io].data(), 64) != 0) {
                    case_bad++;
                    if (bad_tiles < 5) {
                        std::printf("MISMATCH %s tile %zu\n", cs.name.c_str(), io);
                        const int8_t *g = (const int8_t *)top->io_data_output_o_bits.data();
                        const int8_t *e = (const int8_t *)cs.out[io].data();
                        for (int k = 0; k < 64; k++)
                            if (g[k] != e[k]) std::printf("  m %d n %d: got %d expected %d\n", k / 8, k % 8, g[k], e[k]);
                    }
                    bad_tiles++;
                }
                io++;
            }
            tick();
            if (fi) { ii++; v = false; tiles++; }
        }
        top->io_data_input_i_valid = 0;
        top->io_data_output_o_ready = 1;
        top->eval();
        guard = 0;
        while (top->io_busy_o && guard++ < 100) tick();
        bool ok = io == cs.T && ii == cs.T && !top->io_busy_o && case_bad == 0;
        if (!ok) {
            bad_case++;
            std::printf("FAIL %s T=%u map=%08x: out %zu in %zu busy %d bad %ld\n", cs.name.c_str(), cs.T, cs.map, io,
                        ii, top->io_busy_o, case_bad);
        }
        if (cs.map >> 31) {
            en_cases++;
            long gr = (cs.map >> 16) & 0xff;
            if (gr > max_groups_seen) max_groups_seen = gr;
        }
        n_case++;
        cs = Case();
    }
    std::printf("QC SIMD+table TB: %ld cases (%ld with the table, up to %ld groups), %ld tiles, %ld bad cases, "
                "%ld bad tiles -> %s\n", n_case, en_cases, max_groups_seen, tiles, bad_case, bad_tiles,
                (bad_case == 0 && n_case > 0) ? "BIT-EXACT" : "FAIL");
    top->final();
    delete top;
    return (bad_case == 0 && n_case > 0) ? 0 : 1;
}
