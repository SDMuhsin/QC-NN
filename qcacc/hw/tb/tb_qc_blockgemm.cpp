// Verilator testbench of the QC-GeMMX core (snax_acc.qcgemm.QcBlockGemm) against the bit-exact
// M1 array model (qcacc/model/array.py) via the vector file of qcacc/hw/tb/vectors.py.
//   Vtb <vectors.txt> [stall_percent]
// A, B, C are independent decoupled sources and D a sink; with stall_percent > 0 every case
// with an odd index randomly withholds valid / ready (A, B, C, D separately), even cases run
// at full rate and their busy cycles are reported against the ideal M*N*(K+1).
// Exit 0 = every D word of every case bit-exact.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "VQcBlockGemm.h"
#include "verilated.h"

typedef std::vector<uint32_t> Bits;   // little-endian 32-bit words

static Bits parse_hex(const std::string &h) {
    size_t nb = h.size() / 2;
    Bits w((nb + 3) / 4, 0);
    for (size_t i = 0; i < nb; i++) {   // byte i (LSB = 0) is at h[(nb-1-i)*2]
        unsigned v = std::strtoul(h.substr((nb - 1 - i) * 2, 2).c_str(), nullptr, 16);
        w[i / 4] |= v << (8 * (i % 4));
    }
    return w;
}

struct AB { Bits a; uint64_t b; };
struct Case {
    std::string name;
    uint32_t K, N, M, sc;
    std::vector<AB> ab;
    std::vector<Bits> c, d;
};

static bool load(std::ifstream &f, Case &cs) {
    std::string line, tag;
    if (!std::getline(f, line)) return false;
    std::istringstream h(line);
    h >> tag;
    if (tag != "case") return false;
    h >> cs.name >> cs.K >> cs.N >> cs.M >> cs.sc;
    uint32_t T = cs.M * cs.N;
    for (uint32_t t = 0; t < T; t++) {
        for (uint32_t k = 0; k < cs.K; k++) {
            std::getline(f, line);
            std::istringstream s(line);
            std::string a, b;
            s >> tag >> a >> b;
            cs.ab.push_back({parse_hex(a), std::strtoull(b.c_str(), nullptr, 16)});
        }
        std::getline(f, line); { std::istringstream s(line); std::string x; s >> tag >> x; cs.c.push_back(parse_hex(x)); }
        std::getline(f, line); { std::istringstream s(line); std::string x; s >> tag >> x; cs.d.push_back(parse_hex(x)); }
    }
    return true;
}

static VQcBlockGemm *top;
static uint64_t cycle = 0;
static void tick() {
    top->clock = 1; top->eval();
    top->clock = 0; top->eval();
    cycle++;
}

int main(int argc, char **argv) {
    if (argc < 2) { std::fprintf(stderr, "usage: %s vectors.txt [stall_percent]\n", argv[0]); return 2; }
    int stall = argc > 2 ? std::atoi(argv[2]) : 0;
    Verilated::commandArgs(argc, argv);
    top = new VQcBlockGemm;
    std::srand(1);
    top->clock = 0; top->reset = 1; top->eval();
    for (int i = 0; i < 4; i++) tick();
    top->reset = 0; top->eval();

    std::ifstream f(argv[1]);
    Case cs;
    long n_case = 0, bad_case = 0, bad_words = 0, fires = 0;
    long full_cases = 0, full_busy = 0, full_ideal = 0;
    while (load(f, cs)) {
        int st = (n_case % 2) ? stall : 0;
        auto rnd = [&]() { return st > 0 && (std::rand() % 100) < st; };
        // configure
        top->io_ctrl_bits_K_i = cs.K; top->io_ctrl_bits_N_i = cs.N; top->io_ctrl_bits_M_i = cs.M;
        top->io_ctrl_bits_subtraction_constant_i = cs.sc;
        top->io_ctrl_valid = 1;
        top->io_data_a_i_valid = top->io_data_b_i_valid = top->io_data_c_i_valid = 0;
        top->io_data_d_o_ready = 0;
        top->eval();
        int guard = 0;
        while (!top->io_ctrl_ready && guard++ < 1000) tick();
        tick();                                   // ctrl fires on this edge
        top->io_ctrl_valid = 0;
        size_t ia = 0, ib = 0, ic = 0, id = 0;
        bool va = false, vb = false, vc = false;
        long t0 = cycle, case_bad = 0, limit = 50 * (long)cs.ab.size() + 2000;
        while (id < cs.d.size() && (long)(cycle - t0) < limit) {
            if (!va && ia < cs.ab.size() && !rnd()) va = true;
            if (!vb && ib < cs.ab.size() && !rnd()) vb = true;
            if (!vc && ic < cs.c.size() && !rnd()) vc = true;
            top->io_data_a_i_valid = va;
            top->io_data_b_i_valid = vb;
            top->io_data_c_i_valid = vc;
            if (va) std::memcpy(top->io_data_a_i_bits.data(), cs.ab[ia].a.data(), 64);
            if (vb) top->io_data_b_i_bits = cs.ab[ib].b;
            if (vc) std::memcpy(top->io_data_c_i_bits.data(), cs.c[ic].data(), 256);
            top->io_data_d_o_ready = !rnd();
            top->eval();
            bool fa = va && top->io_data_a_i_ready, fb = vb && top->io_data_b_i_ready;
            bool fc = vc && top->io_data_c_i_ready;
            bool fd = top->io_data_d_o_valid && top->io_data_d_o_ready;
            if (fd) {
                if (std::memcmp(top->io_data_d_o_bits.data(), cs.d[id].data(), 256) != 0) {
                    case_bad++;
                    if (bad_words < 5) {
                        std::printf("MISMATCH %s tile %zu\n", cs.name.c_str(), id);
                        for (int w = 0; w < 64; w++)
                            if (top->io_data_d_o_bits[w] != cs.d[id][w])
                                std::printf("  m %d n %d: got %d expected %d\n", w / 8, w % 8,
                                            (int32_t)top->io_data_d_o_bits[w], (int32_t)cs.d[id][w]);
                    }
                    bad_words++;
                }
                id++;
            }
            tick();
            if (fa) { ia++; va = false; fires++; }
            if (fb) { ib++; vb = false; }
            if (fc) { ic++; vc = false; }
        }
        top->io_data_a_i_valid = top->io_data_b_i_valid = top->io_data_c_i_valid = 0;
        top->io_data_d_o_ready = 1;
        top->eval();
        guard = 0;
        while (top->io_busy_o && guard++ < 100) tick();
        bool ok = id == cs.d.size() && ia == cs.ab.size() && ib == cs.ab.size() && ic == cs.c.size()
                  && !top->io_busy_o && case_bad == 0;
        if (!ok) {
            bad_case++;
            std::printf("FAIL %s K=%u N=%u M=%u: d %zu/%zu a %zu b %zu c %zu busy %d bad %ld\n", cs.name.c_str(),
                        cs.K, cs.N, cs.M, id, cs.d.size(), ia, ib, ic, top->io_busy_o, case_bad);
        }
        if (st == 0) {
            full_cases++;
            full_busy += top->io_performance_counter;
            full_ideal += (long)cs.M * cs.N * (cs.K + 1);
        }
        n_case++;
        cs = Case();
    }
    std::printf("QcBlockGemm TB: %ld cases, %ld A/B fires, %ld bad cases, %ld bad D words; "
                "full-rate cases: busy %ld cycles vs M*N*(K+1) = %ld -> %s\n",
                n_case, fires, bad_case, bad_words, full_busy, full_ideal,
                (bad_case == 0 && n_case > 0) ? "BIT-EXACT" : "FAIL");
    top->final();
    delete top;
    return (bad_case == 0 && n_case > 0) ? 0 : 1;
}
