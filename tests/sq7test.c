#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <sys/timeb.h>

#define POOL_SIZE 1024

// wcl386 -q -fp3 -of -lm -l=dos4g sq7test.c

typedef struct {
    float x, y, z;
} vec3;

int in_protected_mode(void) {
    unsigned short msw;
    __asm {
        smsw ax
        mov msw, ax
    }
    return (msw & 1) ? 1 : 0;
}


float Q_rsqrt( float number ) // Quake3 fast inverse sqrt
{
	long i;
	float x2, y;
	const float threehalfs = 1.5F;

	x2 = number * 0.5F;
	y  = number;
	i  = * ( long * ) &y;                       // evil floating point bit level hacking
	i  = 0x5f3759df - ( i >> 1 );               // what the fuck?
	y  = * ( float * ) &i;
	y  = y * ( threehalfs - ( x2 * y * y ) );   // 1st iteration
//	y  = y * ( threehalfs - ( x2 * y * y ) );   // 2nd iteration, this can be removed

	return y;
}


double now_sec(void) // Timer (seconds)
{
    struct timeb t;
    ftime(&t);
    return (double)t.time + (t.millitm / 1000.0);
}

float rand_float(float min, float max)
{
    return min + (max - min) * ((float)rand() / (float)RAND_MAX);
}


vec3 normalize_libc(vec3 v) // Normalization (libc sqrt)
{
    float len = sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    if (len > 0.0f) v.x /= len; v.y /= len; v.z /= len;
    return v;
}


vec3 normalize_qrsqrt(vec3 v) // Normalization (Q_rsqrt)
{
    float len_inv = Q_rsqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    v.x *= len_inv; v.y *= len_inv; v.z *= len_inv;
    return v;
}

int main(int argc, char *argv[]) {
    int i;
	long N = 1000000;   // default iterations
    volatile vec3 sink;
    double t0, t1, time_libc, time_qrsqrt;
    
	vec3 pool[POOL_SIZE];

    if (argc > 1) {
        N = atol(argv[1]);
        if (N <= 0) N = 1000000;
    }

    if (in_protected_mode())
        printf("\nRunning in PROTECTED mode.\n");
    else {
        printf("\nRunning in REAL mode (not supported). Quitting.\n");
        return 1;
    }

	printf("Preparing data...\n");
    srand(42);

    for (i = 0; i < POOL_SIZE; i++) // Pool of random vectors (with mixed magnitudes)
	{
        float vx = rand_float(-100.0f, 100.0f);
        float vy = rand_float(-100.0f, 100.0f);
        float vz = rand_float(-100.0f, 100.0f);

        // occasional large vectors
        if (rand() % 100 < 10)
		{
            vx *= 1000.0f;
            vy *= 1000.0f;
            vz *= 1000.0f;
        }

        pool[i].x = vx;
        pool[i].y = vy;
        pool[i].z = vz;
    }

    // --- LibC sqrt version ---
    t0 = now_sec();
    for (i = 0; i < N; i++) sink = normalize_libc(pool[i % POOL_SIZE]);
    t1 = now_sec();
    time_libc = t1 - t0;

    // --- Quake Q_rsqrt version ---
    t0 = now_sec();
    for (i = 0; i < N; i++) sink = normalize_qrsqrt(pool[i % POOL_SIZE]);
    t1 = now_sec();
    time_qrsqrt = t1 - t0;

	// Output
    printf("\n===== Vector Normalization =====\n");
    printf(" Iterations     : %ld\n", N);
    printf(" Pool size      : %d\n", POOL_SIZE);
    printf(" LibC sqrt()    : %.3f s\n", time_libc);
    printf(" Quake3 rsqrt() : %.3f s\n", time_qrsqrt);

    if (time_qrsqrt < time_libc)
		printf(" Speed up       : %.2fx faster\n", time_libc / time_qrsqrt);
    else
        printf(" Slow down      : %.2fx slower\n", time_qrsqrt / time_libc);

    return 0;
}
