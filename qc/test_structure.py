"""Self-test of qc.structure:  python -m qc.test_structure"""
import numpy as np
import torch

from .structure import decompose, expand, from_matrix, to_matrix


def random_qc(R, Cb, b, signed, rng):
    C = np.zeros((R, Cb, b), np.int8)
    for r in range(R):
        for q in range(Cb):
            n = rng.integers(0, 3)                          # 0, 1 or 2 distinct shifts
            s = rng.choice(b, n, replace=False)
            C[r, q, s] = rng.choice([-1, 1], n) if signed else 1
    return C


def rejects(M, b, signed=False):
    try:
        decompose(M, b, signed)
    except ValueError:
        return True
    return False


def main():
    rng = np.random.default_rng(0)
    for b in (4, 8, 16):
        for signed in (False, True):
            for _ in range(20):
                C = random_qc(4, 9, b, signed, rng)
                M = expand(torch.tensor(C, dtype=torch.float64), b)
                assert (decompose(M, b, signed) == C).all()
                bad = M.clone(); i, j = rng.integers(0, M.shape[0]), rng.integers(0, M.shape[1])
                bad[i, j] = 1 - bad[i, j] if not signed else (0 if bad[i, j] else 1)
                assert rejects(bad, b, signed), "single flipped entry accepted"
            # three shifts, a doubled shift (entries 2), and -1 in unsigned mode
            three = np.zeros((1, 1, b)); three[0, 0, :3] = 1
            assert rejects(expand(torch.tensor(three), b), b, signed)
            two = np.zeros((1, 1, b)); two[0, 0, 1] = 2
            assert rejects(expand(torch.tensor(two), b), b, signed)
        neg = np.zeros((1, 1, b)); neg[0, 0, 1] = -1
        assert rejects(expand(torch.tensor(neg), b), b, False)
        assert not rejects(expand(torch.tensor(neg), b), b, True)
    # weight <-> matrix round trip, both views, incl. cin padding (3 -> 8)
    for view in ("hwc", "chw"):
        for cin, k in ((3, 3), (16, 3), (32, 1)):
            W = torch.randn(16, cin, k, k, dtype=torch.float64)
            M = to_matrix(W, 8, view)
            assert M.shape == (16, k * k * (-(-cin // 8) * 8))
            assert torch.equal(from_matrix(M, cin, k, 8, view), W)
    W = torch.arange(16 * 3 * 9.).reshape(16, 3, 3, 3)
    assert torch.equal(to_matrix(W, 8, "hwc")[:, :3], W[:, :, 0, 0])   # first tap, cin 0..2
    print("qc.structure self-test: PASS")


if __name__ == "__main__":
    main()
