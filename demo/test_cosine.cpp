/**
 * Correctness test for the production workload:
 * IVF256,Flat with METRIC_INNER_PRODUCT, 672-dimensional L2-normalized vectors.
 *
 * Validates that self-queries (a vector queried against itself) return the
 * correct top-1 label and a distance within ±1e-5 of 1.0.
 * Exits with a non-zero status code on failure for CI integration.
 */

#include <cassert>
#include <cmath>
#include <cstdio>
#include <random>
#include <vector>

#include <faiss/IndexFlat.h>
#include <faiss/IndexIVFFlat.h>

int main() {
    const int d = 672;
    const int nb = 10000;
    const int nlist = 256;
    const int nprobe = 32;
    const int k = 1;
    const int nq = 128; // first 128 database vectors used as queries

    // generate random vectors with fixed seed, then L2-normalize
    std::mt19937 rng(42);
    std::uniform_real_distribution<float> distrib(-1.0f, 1.0f);

    std::vector<float> db((size_t)nb * d);
    for (auto& v : db) {
        v = distrib(rng);
    }
    for (int i = 0; i < nb; i++) {
        float norm = 0.0f;
        for (int j = 0; j < d; j++) {
            norm += db[(size_t)i * d + j] * db[(size_t)i * d + j];
        }
        norm = std::sqrt(norm);
        for (int j = 0; j < d; j++) {
            db[(size_t)i * d + j] /= norm;
        }
    }

    // build IVF256,Flat index with inner product metric
    faiss::IndexFlatIP quantizer(d);
    faiss::IndexIVFFlat index(&quantizer, d, nlist, faiss::METRIC_INNER_PRODUCT);
    index.train(nb, db.data());
    index.add(nb, db.data());
    index.nprobe = nprobe;

    // query: each of the first nq vectors should map to itself with distance ≈ 1.0
    std::vector<faiss::idx_t> labels((size_t)k * nq);
    std::vector<float> distances((size_t)k * nq);
    index.search(nq, db.data(), k, distances.data(), labels.data());

    int failures = 0;
    for (int i = 0; i < nq; i++) {
        faiss::idx_t top1 = labels[(size_t)i * k];
        float dist = distances[(size_t)i * k];
        if (top1 != static_cast<faiss::idx_t>(i)) {
            printf("FAIL: query %d top-1 = %lld (expected %d)\n",
                   i, static_cast<long long>(top1), i);
            failures++;
        } else if (std::fabs(dist - 1.0f) > 1e-5f) {
            printf("FAIL: query %d distance = %.8f (expected ~1.0)\n", i, dist);
            failures++;
        }
    }

    if (failures == 0) {
        printf("PASS: all %d self-query top-1 results correct (distance ~1.0)\n", nq);
        return 0;
    }
    printf("FAIL: %d / %d queries did not pass\n", failures, nq);
    return 1;
}
