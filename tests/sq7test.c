// Quake3 fast inverse q_rsqrt() vs Lib C sqrt() comparison benchmark
// v 1.0
// 2025 Dimitar Angelov <funkamateur@gmail.com>
//
// Compile:
// wcl386 -q -d0 -4s -4r -fp5 -mf -ol -ol+ -op -ot -oh -ox -lm -l=dos4g sq7test.c
/*
 -4s 486 stack calling conventions
 -4r 486 register calling conventions
 -fp5 optimize floating point code for Pentium
 -d0 no debugging info
 -ol perform loop optimizations
 -ol+ ol with loop unrolling
 -op improve floating point consistency
 -ot optimize for time (speed)
 -oh enable repeated optimizations
 -ox maximum optimizations
 -ms memory model (small, fast, large)
 
*/


#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <dos.h>
#include <conio.h>

#define POOL_SIZE 1024
#define PIT_FREQ 1193182.0


typedef struct { float x, y, z; } vec3;


int in_protected_mode(void)
{
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


unsigned get_pit(void)
{
    unsigned value;
    outp(0x43, 0x00);             // latch counter 0
    value = inp(0x40);            // low byte
    value |= inp(0x40) << 8;      // high byte
    return value;
}


double pit_time_sec(void)
{
    unsigned count;
    unsigned long bios_ticks;
    unsigned long long total_ticks;

    outp(0x43, 0x00);
    count  = inp(0x40);
    count |= ((unsigned)inp(0x40)) << 8;
    bios_ticks = *(volatile unsigned long*)0x46C;
    total_ticks = ((unsigned long long)bios_ticks << 16) + (0xFFFF - count);

    return (double)total_ticks / PIT_FREQ;
}


float rand_float(float min, float max)
{
    return min + (max - min) * ((float)rand() / (float)RAND_MAX);
}


vec3 normalize_sqrt(vec3 v) // Normalization (libc sqrt)
{
    float len = sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
	if (len > 0.0f)
	{
		v.x /= len;
		v.y /= len;
		v.z /= len;
	}
    return v;
}


vec3 normalize_qrsqrt(vec3 v) // Normalization (Q_rsqrt)
{
    float len_inv = Q_rsqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    v.x *= len_inv; 
	v.y *= len_inv; 
	v.z *= len_inv;
    return v;
}


int main(int argc, char *argv[])
{
    int i;
	long N = 1000000;
    volatile vec3 sink;
	vec3 result, pool[POOL_SIZE];
    double t0, t1, time_sqrt, time_qrsqrt;
	volatile float sink_x = 0, sink_y = 0, sink_z = 0;
	
    if (argc > 1) N = atol(argv[1]);
	
	printf("\nQuake3 Q_rsqrt() vs LibC sqrt() comparison, v1.0\n\n");

    if (in_protected_mode())
        printf("Running in PROTECTED mode.\n");
    else
	{
        printf("Running in REAL mode. Not supported, quitting.\n");
        return 1;
    }

	printf("Preparing data pool ...");
    srand(42);
    for (i = 0; i < POOL_SIZE; i++) // Pool of random vectors (with mixed magnitudes)
	{
        float vx = rand_float(-100.0f, 100.0f);
        float vy = rand_float(-100.0f, 100.0f);
        float vz = rand_float(-100.0f, 100.0f);

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
	
	// LibC sqrt()
	printf("\nTesting LibC sqrt() ...\n");
	t0 = pit_time_sec();
	for (i = 0; i < N; i++)
	{
		result = normalize_sqrt(pool[i & (POOL_SIZE-1)]);
		sink_x = result.x;
		sink_y = result.y;
		sink_z = result.z;
	}
	t1 = pit_time_sec();
	time_sqrt = t1 - t0;
	
	// Pause
	delay(1000);

    // Quake3 Q_rsqrt()
	printf("Testing Quake3 Q_rsqrt() ...\n");
	t0 = pit_time_sec();
	for (i = 0; i < N; i++)
	{
		result = normalize_qrsqrt(pool[i & (POOL_SIZE-1)]);
		sink_x = result.x;
		sink_y = result.y;
		sink_z = result.z;
	}
	t1 = pit_time_sec();
	time_qrsqrt = t1 - t0;

	// Output
    printf("\n==== Vector Normalization ====\n");
    printf(" Iterations  : %ld\n", 		N);
    printf(" Pool size   : %d\n", 		POOL_SIZE);
    printf(" LibC sqrt() : %.6f s\n", 	time_sqrt);
    printf(" Q_rsqrt()   : %.6f s\n",	time_qrsqrt);

    if (time_qrsqrt < time_sqrt)
		printf(" Speeding up : %.6fx faster\n", time_sqrt / time_qrsqrt);
    else
        printf(" Meh ...     : %.6fx slower\n", time_qrsqrt / time_sqrt);

    return 0;
}
