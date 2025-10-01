#include <stdio.h> 
#include <stdlib.h>
#include <math.h>
#include <sys/timeb.h>

//#define ACCUR_ENABLE 1

// wcl386 -q -fp3 -of -lm -l=dos4g sq5test.c

typedef float (*data_generator_t)(int index);

int in_protected_mode(void) {
    unsigned short msw;
    __asm {
        smsw ax
        mov msw, ax
    }
    return (msw & 1) ? 1 : 0;
}

float Q_rsqrt( float number )
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

double now_sec(void) {
    struct timeb t;
    ftime(&t);
    return (double)t.time + (t.millitm / 1000.0);
}

float rand_float(float min, float max) {
    return min + (max - min) * ((float)rand() / (float)RAND_MAX);
}

float powf(float base, float exp) {
    return (float)pow((double)base, (double)exp);
}

float run_benchmark(const char *name, data_generator_t gen_func, int size) 
{
    volatile float sink;
    double t0, t1, time_libc, time_qrsqrt, total_abs_err, total_rel_err, avg_abs_err, avg_rel_err;
	int i;
	float max_abs_err, max_rel_err, tdiff;
	
	printf("===== %s =====\nRunning ...\n", name);

    // libc sqrtf
    t0 = now_sec();
    for (i = 0; i < size; i++) sink = sqrt(gen_func(i));
    t1 = now_sec();
	time_libc = t1 - t0;

    // Q_rsqrt
    t0 = now_sec();
    for (i = 0; i < size; i++) sink = 1.0f / Q_rsqrt(gen_func(i));
    t1 = now_sec();
    time_qrsqrt = t1 - t0;

    // Accuracy
	#ifdef ACCUR_ENABLE
    total_abs_err = 0.0, total_rel_err = 0.0;
    max_abs_err = 0.0, max_rel_err = 0.0;
    for (i = 0; i < size; i++) 
	{
        float x = gen_func(i);
        float lib_sqrt = sqrt(x);
        float qsqrt = 1.0f / Q_rsqrt(x);
        float abs_err = fabs(lib_sqrt - qsqrt);
        float rel_err = abs_err / lib_sqrt;

        total_abs_err += abs_err;
        total_rel_err += rel_err;

        if (abs_err > max_abs_err) max_abs_err = abs_err;
        if (rel_err > max_rel_err) max_rel_err = rel_err;
    }
	
	avg_abs_err = total_abs_err / size;
    avg_rel_err = total_rel_err / size;
	#endif

    printf("Performance:\n");
	printf(" Iterations\t  : %i\n", size);
    printf(" LibC sqrt()\t  : %.3f s\n", time_libc);
    printf(" Quake3 Q_rsqrt() : %.3f s\n", time_qrsqrt);
	tdiff = time_libc / time_qrsqrt;
	if(tdiff < 1.0f) 
	{
		tdiff = time_qrsqrt / time_libc;
		printf(" Speed diff\t  : %.2fx slower\n\n", tdiff);
	}
	else
		printf(" Speed diff\t  : %.2fx faster\n\n", tdiff);

	#ifdef ACCUR_ENABLE
    printf("Accuracy:\n");
    printf("  Avg abs error: %.6f\n", avg_abs_err);
    printf("  Avg rel error: %.6f%%\n", avg_rel_err * 100.0);
    printf("  Max abs error: %.6f\n", max_abs_err);
    printf("  Max rel error: %.6f%%\n\n", max_rel_err * 100.0);
	#endif
	
	return tdiff;
}

// Data generators
float linear_gen(int i) {
    return (float)(i + 1);
}

float random_vectors_gen(int i) {
    float vx = rand_float(-100.0f, 100.0f);
    float vy = rand_float(-100.0f, 100.0f);
    float vz = rand_float(-100.0f, 100.0f);
    return vx*vx + vy*vy + vz*vz;
}

float mixed_lengths_gen(int i) {
    if (rand() % 100 < 90) 
        return rand_float(0.01f, 100.0f); // 90% small
    else 
        return rand_float(100.0f, 4000000.0f); // 10% large
}

float log_uniform_gen(int i) {
    float r = (float)rand() / RAND_MAX;
    return powf(10.0f, r * 6.0f); // 1 → 1,000,000
}

int main(int argc, char *argv[])
{
	float tres;
	long N = 1000000;
	
	if (in_protected_mode())
        printf("Running in PROTECTED mode.\n");
    else
	{
		printf("Running in REAL mode.\n");
		return 1;
	}
        
    if (argc > 1) {
		printf("Iterations: %s\n", argv[1]);
        N = atol(argv[1]);
    }

	printf("\nStarting tests (4)...\n");

    srand(42);

    // --- Linear range ---
    tres = run_benchmark("Linear range", linear_gen, N);
	
    // --- Random vectors (squared lengths) ---
    tres += run_benchmark("Random 3D vectors", random_vectors_gen, N);
	
    // --- Mixed vector lengths (mostly small, occasional large) ---
    tres += run_benchmark("Mixed vector lengths", mixed_lengths_gen, N);
	
    // --- Log-uniform distribution ---
    tres += run_benchmark("Log-uniform distribution", log_uniform_gen, N);
	
	printf("Average speed difference: %.2fx\n", tres / 4);

    return 0;
}
