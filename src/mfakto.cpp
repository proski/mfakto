/* OpenCL specific code for trial factoring */

#include <cstdlib>
#include <iostream>
#include <string>
#include <fstream>
#include <CL/cl.h>
#include "params.h"
#include "my_types.h"
#include "compatibility.h"
#include "read_config.h"
#include "parse.h"
#include "sieve.h"
#include "timer.h"
#include "checkpoint.h"
#include "mfakto.h"

/* Global variables */

cl_uint             new_class=1;
cl_context          context=NULL;
cl_device_id        *devices;
cl_command_queue    commandQueue;
cl_program          program;

#ifdef __cplusplus
extern "C"
{
#endif

extern mystuff_t    mystuff;
OpenCL_deviceinfo_t deviceinfo={0};
kernel_info_t       kernel_info[NUM_KERNELS] = {
  /*   kernel (in sequence) | kernel function name | bit_min | bit_max | loaded kernel pointer */
         AUTOSELECT_KERNEL,   "auto",                  0,      0,         NULL,
         _TEST_MOD_,          "mod_128_64_k",          0,      0,         NULL,
         _64BIT_64_OpenCL,    "mfakto_cl_64",          0,     64,         NULL,
         _95BIT_64_OpenCL,    "mfakto_cl_95",         63,     95,         NULL,
         BARRETT92_64_OpenCL, "mfakto_cl_barrett92",  64,     92,         NULL,
         _71BIT_MUL24,        "mfakto_cl_71",          0,     71,         NULL,
         UNKNOWN_KERNEL,      "UNKNOWN kernel",        0,      0,         NULL
};

/* not implemented (yet):
         BARRETT72_MUL24
         _95BIT_MUL32,        "95bit_mul32",         0, 95, NULL,
         BARRETT79_MUL32,     "barrett79_mul32",    64, 79, NULL,
         BARRETT92_MUL32,     "barrett92_mul32",    64, 92, NULL,
         */


/* allocate memory buffer arrays, test a small kernel */
int init_CLstreams(void)
{
  int i;
  cl_int status;

  if (context==NULL)
  {
    fprintf(stderr, "invalid context.\n");
    return 1;
  }

  for(i=0;i<(mystuff.num_streams);i++)
  {
    mystuff.stream_status[i] = UNUSED;
    if( (mystuff.h_ktab[i] = (unsigned int *) malloc( mystuff.threads_per_grid * sizeof(int))) == NULL )
    {
      printf("ERROR: malloc(h_ktab[%d]) failed\n", i);
      return 1;
    }
    mystuff.d_ktab[i] = clCreateBuffer(context, 
                      CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR,
                      mystuff.threads_per_grid * sizeof(int),
                      mystuff.h_ktab[i], 
                      &status);
    if(status != CL_SUCCESS) 
  	{ 
	  	std::cout<<"Error " << status << ": clCreateBuffer (h_ktab[" << i << "]) \n";
	  	return 1;
	  }
  }
  if( (mystuff.h_RES = (unsigned int *) malloc(32 * sizeof(int))) == NULL )
  {
    printf("ERROR: malloc(h_RES) failed\n");
    return 1;
  }
  mystuff.d_RES = clCreateBuffer(context, 
                    CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR,
                    32 * sizeof(int),
                    mystuff.h_RES, 
                    &status);
  if(status != CL_SUCCESS) 
  { 
		std::cout<<"Error " << status << ": clCreateBuffer (d_RES)\n";
		return 1;
	}
	return 0;
}


/*
 * init_CL: all OpenCL-related one-time inits:
 *   create context, devicelist, command queue, 
 *   load kernel file, compile, link CL source, build program and kernels
 */
int init_CL(int num_streams, cl_uint devnumber)
{
  cl_int status;
  size_t dev_s;
  cl_uint numplatforms, i;
  cl_platform_id platform = NULL;
  cl_platform_id* platformlist = NULL;

  status = clGetPlatformIDs(0, NULL, &numplatforms);
  if(status != CL_SUCCESS)
  {
    std::cerr << "Error " << status << ": clGetPlatformsIDs(num)\n";
    return 1;
  }

  if(numplatforms > 0)
  {
    platformlist = new cl_platform_id[numplatforms];
    status = clGetPlatformIDs(numplatforms, platformlist, NULL);
    if(status != CL_SUCCESS)
    {
      std::cerr << "Error " << status << ": clGetPlatformsIDs\n";
      return 1;
    }

    if (devnumber > 10) // platform number specified as part of -d
    {
      i = devnumber/10 - 1;
      if (i < numplatforms)
      {
        platform = platformlist[i];
#ifdef DETAILED_INFO
        char buf[128];
        status = clGetPlatformInfo(platform, CL_PLATFORM_VENDOR,
                        sizeof(buf), buf, NULL);
        if(status != CL_SUCCESS)
        {
          std::cerr << "Error " << status << ": clGetPlatformInfo(VENDOR)\n";
          return 1;
        }
        std::cout << "OpenCL Platform " << i+1 << "/" << numplatforms << ": " << buf;

        status = clGetPlatformInfo(platform, CL_PLATFORM_VERSION,
                        sizeof(buf), buf, NULL);
        if(status != CL_SUCCESS)
        {
          std::cerr << "Error " << status << ": clGetPlatformInfo(VERSION)\n";
          return 1;
        }
        std::cout << ", Version: " << buf << std::endl;
#endif
      }
      else
      {
        fprintf(stderr, "Error: Only %d platforms found. Cannot use platform %d (bad parameter to option -d).\n", numplatforms, i);
        return 1;
      }
    }
    else for(i=0; i < numplatforms; i++) // autoselect: search for AMD
    {
      char buf[128];
      status = clGetPlatformInfo(platformlist[i], CL_PLATFORM_VENDOR,
                        sizeof(buf), buf, NULL);
      if(status != CL_SUCCESS)
      {
        std::cerr << "Error " << status << ": clGetPlatformInfo(VENDOR)\n";
        return 1;
      }
      if(strncmp(buf, "Advanced Micro Devices, Inc.", sizeof(buf)) == 0)
      {
        platform = platformlist[i];
      }
#ifdef DETAILED_INFO
      std::cout << "OpenCL Platform " << i+1 << "/" << numplatforms << ": " << buf;

      status = clGetPlatformInfo(platformlist[i], CL_PLATFORM_VERSION,
                        sizeof(buf), buf, NULL);
      if(status != CL_SUCCESS)
      {
        std::cerr << "Error " << status << ": clGetPlatformInfo(VERSION)\n";
        return 1;
      }
      std::cout << ", Version: " << buf << std::endl;
#endif
    }
  }

  delete[] platformlist;
  
  if(platform == NULL)
  {
    std::cerr << "Error: No platform found\n";
    return 1;
  }

  cl_context_properties cps[3] = { CL_CONTEXT_PLATFORM, (cl_context_properties)platform, 0 };
  context = clCreateContextFromType(cps, CL_DEVICE_TYPE_GPU, NULL, NULL, &status);
  if (status == CL_DEVICE_NOT_FOUND)
  {
    clReleaseContext(context);
    std::cout << "GPU not found, fallback to CPU." << std::endl;
    context = clCreateContextFromType(cps, CL_DEVICE_TYPE_CPU, NULL, NULL, &status);
    if(status != CL_SUCCESS) 
  	{  
   	  std::cerr << "Error " << status << ": clCreateContextFromType(CPU)\n";
	    return 1; 
    }
  }
  else if(status != CL_SUCCESS) 
	{  
		std::cerr << "Error " << status << ": clCreateContextFromType(GPU)\n";
		return 1;
  }

  cl_uint num_devices;
  status = clGetContextInfo(context, CL_CONTEXT_NUM_DEVICES, sizeof(num_devices), &num_devices, NULL);
  if(status != CL_SUCCESS) 
	{ 
		std::cerr << "Error " << status << ": clGetContextInfo(CL_CONTEXT_NUM_DEVICES) - assuming one device\n";
		// return 1;
    num_devices = 1;
	}

  status = clGetContextInfo(context, CL_CONTEXT_DEVICES, 0, NULL, &dev_s);
  if(status != CL_SUCCESS) 
	{  
		std::cerr << "Error " << status << ": clGetContextInfo(numdevs)\n";
		return 1;
	}

	if(dev_s == 0)
	{
		std::cerr << "Error: no devices.\n";
		return 1;
	}

  devices = (cl_device_id *)malloc(dev_s*sizeof(cl_device_id));  // *sizeof(...) should not be needed (dev_s is in bytes)
	if(devices == 0)
	{
		std::cerr << "Error: Out of memory.\n";
		return 1;
	}

  status = clGetContextInfo(context, CL_CONTEXT_DEVICES, dev_s*sizeof(cl_device_id), devices, NULL);
  if(status != CL_SUCCESS) 
	{ 
		std::cerr << "Error " << status << ": clGetContextInfo(devices)\n";
		return 1;
	}

  devnumber = devnumber % 10;  // use only the last digit as device number, counting from 1
  cl_uint dev_from=0, dev_to=num_devices;
  if (devnumber > 0)
  {
    if (devnumber > num_devices)
    {
      fprintf(stderr, "Error: Only %d devices found. Cannot use device %d (bad parameter to option -d).\n", num_devices, devnumber);
      return 1;
    }
    else
    {
      dev_to    = devnumber;    // tweak the loop to run only once for our device
      dev_from  = --devnumber;  // index from 0
    }
  }
   
  for (i=dev_from; i<dev_to; i++)
  {

    status = clGetDeviceInfo(devices[i], CL_DEVICE_NAME, sizeof(deviceinfo.d_name), deviceinfo.d_name, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_NAME)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_VERSION, sizeof(deviceinfo.d_ver), deviceinfo.d_ver, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_VERSION)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_VENDOR, sizeof(deviceinfo.v_name), deviceinfo.v_name, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_VENDOR)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DRIVER_VERSION, sizeof(deviceinfo.dr_version), deviceinfo.dr_version, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DRIVER_VERSION)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_EXTENSIONS, sizeof(deviceinfo.exts), deviceinfo.exts, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_EXTENSIONS)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_GLOBAL_MEM_CACHE_SIZE, sizeof(deviceinfo.gl_cache), &deviceinfo.gl_cache, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_GLOBAL_MEM_CACHE_SIZE)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_GLOBAL_MEM_SIZE, sizeof(deviceinfo.gl_mem), &deviceinfo.gl_mem, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_GLOBAL_MEM_SIZE)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_MAX_CLOCK_FREQUENCY, sizeof(deviceinfo.max_clock), &deviceinfo.max_clock, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_MAX_CLOCK_FREQUENCY)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_MAX_COMPUTE_UNITS, sizeof(deviceinfo.units), &deviceinfo.units, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_MAX_COMPUTE_UNITS)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_MAX_WORK_GROUP_SIZE, sizeof(deviceinfo.wg_size), &deviceinfo.wg_size, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_MAX_WORK_GROUP_SIZE)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS, sizeof(deviceinfo.w_dim), &deviceinfo.w_dim, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_MAX_WORK_ITEM_SIZES, sizeof(deviceinfo.wi_sizes), deviceinfo.wi_sizes, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_MAX_WORK_ITEM_SIZES)\n";
	  	return 1;
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_LOCAL_MEM_SIZE, sizeof(deviceinfo.l_mem), &deviceinfo.l_mem, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_LOCAL_MEM_SIZE)\n";
	  	return 1;
	  }
    
#ifdef DETAILED_INFO
    std::cout << "Device " << i+1  << "/" << num_devices << ": " << deviceinfo.d_name << " (" << deviceinfo.v_name << "),\ndevice version: "
      << deviceinfo.d_ver << ", driver version: " << deviceinfo.dr_version << "\nExtensions: " << deviceinfo.exts
      << "\nGlobal memory:" << deviceinfo.gl_mem << ", Global memory cache: " << deviceinfo.gl_cache
      << ", local memory: " << deviceinfo.l_mem << ", workgroup size: " << deviceinfo.wg_size << ", Work dimensions: " << deviceinfo.w_dim
      << "[" << deviceinfo.wi_sizes[0] << ", " << deviceinfo.wi_sizes[1] << ", " << deviceinfo.wi_sizes[2] << ", " << deviceinfo.wi_sizes[3] << ", " << deviceinfo.wi_sizes[4]
      << "] , Max clock speed:" << deviceinfo.max_clock << ", compute units:" << deviceinfo.units << std::endl;
#endif // DETAILED_INFO
  }

  deviceinfo.maxThreadsPerBlock = deviceinfo.wi_sizes[0];
  deviceinfo.maxThreadsPerGrid  = deviceinfo.wi_sizes[0];
  for (i=1; i<deviceinfo.w_dim && i<5; i++)
  {
    if (deviceinfo.wi_sizes[i])
      deviceinfo.maxThreadsPerGrid *= deviceinfo.wi_sizes[i];
  }

//  cl_command_queue_properties props = 0;
  cl_command_queue_properties props = CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE;  // kernels and copy-jobs are queued with event dependencies, so this should work ...
#ifdef CL_PERFORMANCE_INFO
  props |= CL_QUEUE_PROFILING_ENABLE;
#endif

  commandQueue = clCreateCommandQueue(context, devices[devnumber], props, &status);
  if(status != CL_SUCCESS) 
	{ 
    std::cerr << "Error " << status << ": clCreateCommandQueue(dev#" << devnumber+1 << ")\n";
		return 1;
	}

	size_t size;
	char*  source;

	std::fstream f(KERNEL_FILE, (std::fstream::in | std::fstream::binary));

	if(f.is_open())
	{
		f.seekg(0, std::fstream::end);
		size = (size_t)f.tellg();
		f.seekg(0, std::fstream::beg);

		source = (char *) malloc(size+1);
		if(!source)
		{
			f.close();
      std::cerr << "\noom\n";
			return 1;
		}

		f.read(source, size);
		f.close();
		source[size] = '\0';
  }
	else
	{
		std::cerr << "\nKernel file ""KERNEL_FILE"" not found, it needs to be in the same directory as the executable.\n";
		return 1;
	}

  program = clCreateProgramWithSource(context, 1, (const char **)&source, &size, &status);
	if(status != CL_SUCCESS) 
	{ 
	  std::cerr << "Error " << status << ": clCreateProgramWithSource\n";
	  return 1;
	}

  status = clBuildProgram(program, 1, &devices[devnumber], "-O3", NULL, NULL);
  if(status != CL_SUCCESS) 
  { 
#ifdef DETAILED_INFO
    if(status == CL_BUILD_PROGRAM_FAILURE)
    {
      cl_int logstatus;
      char *buildLog = NULL;
      size_t buildLogSize = 0;
      logstatus = clGetProgramBuildInfo (program, devices[devnumber], CL_PROGRAM_BUILD_LOG, 
                buildLogSize, buildLog, &buildLogSize);
      if(logstatus != CL_SUCCESS)
      {
        std::cerr << "Error " << logstatus << ": clGetProgramBuildInfo failed.";
        return 1;
      }
      buildLog = (char*)calloc(buildLogSize,1);
      if(buildLog == NULL)
      {
        std::cerr << "\noom\n";
        return 1;
      }
      fflush(NULL);
      logstatus = clGetProgramBuildInfo (program, devices[devnumber], CL_PROGRAM_BUILD_LOG, 
                buildLogSize, buildLog, NULL);
      if(logstatus != CL_SUCCESS)
      {
        std::cerr << "Error " << logstatus << ": clGetProgramBuildInfo failed.";
        free(buildLog);
        return 1;
      }

      std::cout << " \n\tBUILD OUTPUT\n";
      std::cout << buildLog << std::endl;
      std::cout << " \tEND OF BUILD OUTPUT\n";
      free(buildLog);
    }
#endif
		std::cerr<<"Error " << status << ": clBuildProgram\n";
		return 1; 
  }

  free(source);  

  /* get kernel by name */
  kernel_info[_64BIT_64_OpenCL].kernel = clCreateKernel(program, kernel_info[_64BIT_64_OpenCL].kernelname, &status);
  if(status != CL_SUCCESS) 
	{  
		std::cerr<<"Error " << status << ": Creating Kernel " << kernel_info[_64BIT_64_OpenCL].kernelname << " from program. (clCreateKernel)\n";
		return 1;
	}

  kernel_info[BARRETT92_64_OpenCL].kernel = clCreateKernel(program, kernel_info[BARRETT92_64_OpenCL].kernelname, &status);
  if(status != CL_SUCCESS) 
	{  
		std::cerr<<"Error " << status << ": Creating Kernel " << kernel_info[BARRETT92_64_OpenCL].kernelname << " from program. (clCreateKernel)\n";
		return 1;
	}

  kernel_info[_TEST_MOD_].kernel = clCreateKernel(program, kernel_info[_TEST_MOD_].kernelname, &status);
  if(status != CL_SUCCESS) 
	{  
		std::cerr<<"Error " << status << ": Creating Kernel " << kernel_info[_TEST_MOD_].kernelname << " from program. (clCreateKernel)\n";
		return 1;
	}

  kernel_info[_95BIT_64_OpenCL].kernel = clCreateKernel(program, kernel_info[_95BIT_64_OpenCL].kernelname, &status);
  if(status != CL_SUCCESS) 
	{  
		std::cerr<<"Error " << status << ": Creating Kernel " << kernel_info[_95BIT_64_OpenCL].kernelname << " from program. (clCreateKernel)\n";
		return 1;
	}

  kernel_info[_71BIT_MUL24].kernel = clCreateKernel(program, kernel_info[_71BIT_MUL24].kernelname, &status);
  if(status != CL_SUCCESS) 
	{  
		std::cerr<<"Error " << status << ": Creating Kernel " << kernel_info[_71BIT_MUL24].kernelname << " from program. (clCreateKernel)\n";
		return 1;
	}
  return 0;
}


#ifdef __cplusplus
}
#endif


/* error callback function - not used right now */
	void  CL_CALLBACK CL_error_cb(const char *errinfo,
  	const void  *private_info,
  	size_t  cb,
  	void  *user_data)
  {
    std::cerr << "Error callback: " << errinfo << std::endl;
  }


int run_mod_kernel(cl_ulong hi, cl_ulong lo, cl_ulong q, cl_float qr, cl_ulong *res_hi, cl_ulong *res_lo)
{
/* __kernel void mod_128_64_k(const ulong hi, const ulong lo, const ulong q, const float qr, __global ulong *res 
#if (TRACE_KERNEL > 1)
                  , __private uint tid
#endif
)
*/
  cl_int   status;
  cl_event mod_evt;

  *res_hi = *res_lo = 0;

  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    0, 
                    sizeof(cl_ulong), 
                    (void *)&hi);
  if(status != CL_SUCCESS) 
	{ 
		std::cout<<"Error " << status << ": Setting kernel argument. (hi)\n";
		return 1;
	}
  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    1, 
                    sizeof(cl_ulong), 
                    (void *)&lo);
  if(status != CL_SUCCESS) 
	{ 
		std::cout<<"Error " << status << ": Setting kernel argument. (lo)\n";
		return 1;
	}
  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    2, 
                    sizeof(cl_ulong), 
                    (void *)&q);
  if(status != CL_SUCCESS) 
	{ 
		std::cout<<"Error " << status << ": Setting kernel argument. (q)\n";
		return 1;
	}
  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    3, 
                    sizeof(cl_float), 
                    (void *)&qr);
  if(status != CL_SUCCESS) 
	{ 
		std::cout<<"Error " << status << ": Setting kernel argument. (qr)\n";
		return 1;
	}
  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    4, 
                    sizeof(cl_mem), 
                    (void *)&mystuff.d_RES);
  if(status != CL_SUCCESS) 
	{ 
		std::cout<<"Error " << status << ": Setting kernel argument. (RES)\n";
		return 1;
	}
  // dummy arg if KERNEL_TRACE is enabled: ignore errors if not.
  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    5, 
                    sizeof(cl_uint), 
                    (void *)&status);

  status = clEnqueueTask(commandQueue,
                 kernel_info[_TEST_MOD_].kernel,
                 0,
                 NULL,
                 &mod_evt);
  if(status != CL_SUCCESS) 
	{ 
		std::cerr<< "Error " << status << ": Enqueueing kernel(clEnqueueTask)\n";
		return 1;
	}

  status = clWaitForEvents(1, &mod_evt); 
  if(status != CL_SUCCESS) 
  { 
	  std::cerr<< "Error " << status << ": Waiting for mod call to finish. (clWaitForEvents)\n";
	  return 1;
  }
  #ifdef CL_PERFORMANCE_INFO
              cl_ulong startTime;
              cl_ulong endTime;
              /* Get kernel profiling info */
              status = clGetEventProfilingInfo(mod_evt,
                                CL_PROFILING_COMMAND_START,
                                sizeof(cl_ulong),
                                &startTime,
                                0);
              if(status != CL_SUCCESS)
 	            { 
		            std::cerr<< "Error " << status << " in clGetEventProfilingInfo.(startTime)\n";
                return 1;
              }
              status = clGetEventProfilingInfo(mod_evt,
                                CL_PROFILING_COMMAND_END,
                                sizeof(cl_ulong),
                                &endTime,
                                0);
              if(status != CL_SUCCESS)
 	            { 
		            std::cerr<< "Error " << status << " in clGetEventProfilingInfo.(endTime)\n";
                return 1;
              }
              std::cout<< "mod_kernel finished in " << (endTime - startTime)/1e3 << " us.\n" ;
#endif

  status = clReleaseEvent(mod_evt);
  if(status != CL_SUCCESS) 
  { 
		std::cerr<< "Error " << status << ": Release mod event object. (clReleaseEvent)\n";
	  return 1;
  }
  status = clEnqueueReadBuffer(commandQueue,
                mystuff.d_RES,
                CL_TRUE,
                0,
                32 * sizeof(int),
                mystuff.h_RES,
                0,
                NULL,
                NULL);
    
  if(status != CL_SUCCESS) 
	{ 
    std::cout << "Error " << status << ": clEnqueueReadBuffer RES failed. (clEnqueueReadBuffer)\n";
		return 1;
  }
  *res_hi = mystuff.h_RES[0];
  *res_lo = mystuff.h_RES[1];

	return 0;

}

int run_kernel24(cl_kernel l_kernel, cl_uint exp, int72 k_base, int stream, int144 b_preinit, cl_mem res, cl_int shiftcount)
/*
  run_kernel24(kernel_info[use_kernel].kernel, exp, k_base, i, b_preinit, mystuff->d_RES, shiftcount);
*/
{
  cl_int   status;
  /*
  __kernel void mfakto_cl_71(__private uint exp, __private int72_t k_base, __global uint *k_tab, __private int shiftcount, __private int144_t b, __global uint *RES)
*/
  //////// test test test ...
  // {k_min_grid[i] = 1777608657747ULL; mystuff->h_ktab[i][0]=0;}
  // k_base.d2=0;
  // k_base.d1=0;
  // k_base.d0=1;
  // new_class=1;
  ///////

  // first set the specific params that don't change per block: b_preinit, shiftcount, RES
  if (new_class)
  {
    status = clSetKernelArg(l_kernel, 
                    3, 
                    sizeof(cl_int), 
                    (void *)&shiftcount);
    if(status != CL_SUCCESS) 
  	{ 
  		std::cerr<< "Error " << status << ": Setting kernel argument. (shiftcount)\n";
  		return 1;
  	}
    status = clSetKernelArg(l_kernel, 
                    4, 
                    sizeof(int144), 
                    (void *)&b_preinit);
    if(status != CL_SUCCESS) 
  	{ 
  		std::cerr<< "Error " << status << ": Setting kernel argument. (b_preinit)\n";
  		return 1;
  	}
#ifdef DETAILED_INFO
    printf("run_kernel24: b=%x:%x:%x:%x:%x:%x, shift=%d\n", b_preinit.d5, b_preinit.d4, b_preinit.d3, b_preinit.d2, b_preinit.d1, b_preinit.d0, shiftcount);
#endif

  }
  // now the params that change everytime
  status = clSetKernelArg(l_kernel, 
                    1, 
                    sizeof(int72), 
                    (void *)&k_base);
  if(status != CL_SUCCESS) 
	{ 
		std::cerr<<"Error " << status << ": Setting kernel argument. (k_base)\n";
		return 1;
	}
#ifdef DETAILED_INFO
  printf("run_kernel24: k_base=%x:%x:%x\n", k_base.d2, k_base.d1, k_base.d0);
#endif
    
  return run_kernel(l_kernel, exp, stream, res); // set params 0,2,5 and start the kernel
}

int run_kernel64(cl_kernel l_kernel, cl_uint exp, cl_ulong k_base, int stream, cl_ulong4 b_preinit, cl_mem res, cl_int bin_min63)
{
/*
 *	        cl_ulong4 b_preinit = {b_preinit_lo, b_preinit_mid, b_preinit_hi, shiftcount};
        run_kernel(kernel, exp, k_base, mystuff->d_ktab[stream], b_preinit, bit_min-63, mystuff->d_RES);
 */
  cl_int   status;
  /* __kernel void mfakto_cl_95(uint exp, ulong k, __global uint *k_tab, ulong4 b_pre_shift, int bit_max64, __global uint *RES) */
  // first set the specific params that don't change per block: b_pre_shift, bin_min63
  if (new_class)
  {
    status = clSetKernelArg(l_kernel, 
                    3, 
                    sizeof(cl_ulong4), 
                    (void *)&b_preinit);
    if(status != CL_SUCCESS) 
  	{ 
  		std::cerr<< "Error " << status << ": Setting kernel argument. (b_preinit)\n";
  		return 1;
  	}

    /* the bit_max-64 for the barrett kernels (the others ignore it) */
    status = clSetKernelArg(l_kernel, 
                    4, 
                    sizeof(cl_int), 
                    (void *)&bin_min63);
    if(status != CL_SUCCESS) 
  	{ 
	  	std::cerr<<"Warning " << status << ": Setting kernel argument. (bit_min)\n";
  		
  	}
#ifdef DETAILED_INFO
    printf("run_kernel64: b=%llx:%llx:%llx, shift=%lld\n", b_preinit.s[0], b_preinit.s[1], b_preinit.s[2], b_preinit.s[3]);
#endif
  }
  // now the params that change everytime
  status = clSetKernelArg(l_kernel, 
                    1, 
                    sizeof(cl_ulong), 
                    (void *)&k_base);
  if(status != CL_SUCCESS) 
	{ 
		std::cerr<<"Error " << status << ": Setting kernel argument. (k_base)\n";
		return 1;
	}
#ifdef DETAILED_INFO
  printf("run_kernel64: kbase=%lld\n", k_base);
#endif
  return run_kernel(l_kernel, exp, stream, res);
}

int run_kernel(cl_kernel l_kernel, cl_uint exp, int stream, cl_mem res)
{
  cl_int   status;
  cl_mem   k_tab = mystuff.d_ktab[stream];
  size_t   globalThreads[2];
    
  globalThreads[0] = (mystuff.threads_per_grid > deviceinfo.maxThreadsPerBlock) ? deviceinfo.maxThreadsPerBlock : mystuff.threads_per_grid;
  globalThreads[1] = (mystuff.threads_per_grid > deviceinfo.maxThreadsPerBlock) ? mystuff.threads_per_grid/deviceinfo.maxThreadsPerBlock : 1;


  // first set the params that don't change per block: exp, RES
  if (new_class)
  {
    status = clSetKernelArg(l_kernel, 
                    0, 
                    sizeof(cl_uint), 
                    (void *) &exp);
    if(status != CL_SUCCESS) 
	  { 
	  	std::cerr<<"Error " << status << ": Setting kernel argument. (exp)\n";
	  	return 1;
  	}

    /* the output array to the kernel */
    status = clSetKernelArg(l_kernel, 
                    5, 
                    sizeof(cl_mem), 
                    (void *)&res);
    if(status != CL_SUCCESS) 
  	{ 
	  	std::cerr<<"Error " << status << ": Setting kernel argument. (res)\n";
  		return 1;
  	}

    new_class = 0; // do not set these params again until a new class is started
  }

  status = clSetKernelArg(l_kernel, 
                    2, 
                    sizeof(cl_mem), 
                    (void *)&k_tab);
  if(status != CL_SUCCESS) 
	{ 
		std::cerr<<"Error " << status << ": Setting kernel argument. (k_tab)\n";
		return 1;
	}

  status = clEnqueueNDRangeKernel(commandQueue,
                 l_kernel,
                 2,
                 NULL,
                 globalThreads,
                 NULL,
                 1,
                 &mystuff.copy_events[stream], // wait for the k_tab write to finish
                 &mystuff.exec_events[stream]);
  if(status != CL_SUCCESS) 
	{ 
		std::cerr<< "Error " << status << ": Enqueueing kernel(clEnqueueNDRangeKernel)\n";
		return 1;
	}
  clFlush(commandQueue);
	return 0;
}

int cleanup_CL(void)
{
  cl_int status, i;

  for (i=0; i<NUM_KERNELS; i++)
  {
    if (kernel_info[i].kernel)
    {
      status = clReleaseKernel(kernel_info[i].kernel);
      if(status != CL_SUCCESS)
    	{
	    	fprintf(stderr, "Error %d: clReleaseKernel(%d)\n", status, i);
	    	return 1; 
      }
  	}
  }

  status = clReleaseProgram(program);
  if(status != CL_SUCCESS)
	{
		std::cerr<<"Error" << status << ": clReleaseProgram\n";
		return 1; 
	}
  for (i=0; i<mystuff.num_streams; i++)
  {
    status = clReleaseMemObject(mystuff.d_ktab[i]);
    if(status != CL_SUCCESS)
  	{
	  	std::cerr<<"Error" << status << ": clReleaseMemObject (d_ktab" << i << ")\n";
  		return 1; 
  	}
    free(mystuff.h_ktab[i]);
  }
	status = clReleaseMemObject(mystuff.d_RES);
  if(status != CL_SUCCESS)
	{
		std::cerr<<"Error" << status << ": clReleaseMemObject (dRES)\n";
		return 1; 
	}
  free(mystuff.h_RES);
  status = clReleaseCommandQueue(commandQueue);
  if(status != CL_SUCCESS)
	{
		std::cerr<<"Error" << status << ": clReleaseCommandQueue\n";
		return 1;
	}
  status = clReleaseContext(context);
  if(status != CL_SUCCESS)
	{
		std::cerr<<"Error" << status << ": clReleaseContext\n";
		return 1;
	}
  if(devices != NULL)
  {
      free(devices);
      devices = NULL;
  }
	return 0;
}

void print1DArray(const char * Name, const unsigned int * Data, const unsigned int len)
{
    cl_uint i, o;

    o = printf("%s: ", Name);
    for(i = 0; i < len && o < 300; i++) // limit to ~ 4 lines (~ 4x80 chars)
    {
        o += printf("%d ", Data[i]);
    }
    printf("... %d %d\n", Data[len-2], Data[len-1]);
}

bool prime(cl_ulong pp, bool quick)
{
  cl_ulong i=0;
  if (quick)
  {
    cl_uint primes[]={3,5,7,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71,73,79,83,89,91,97,0};

    int j=primes[i];
    while (j)
    {
      if (pp == j)   return true;
      if (pp%j == 0) return false;
      j=primes[++i];
    }
  }
  else
  {
    for (i=3; i*i<=pp;i+=2)
      if (pp%i == 0) return false;
  }
  return true;
}

void print_dez72(int72 a, char *buf)
/*
writes "a" into "buf" in decimal
"buf" must be at least 25 bytes
*/
{
  char digit[24];
  int digits=0,carry,i=0;
  
  while((a.d0!=0 || a.d1!=0 || a.d2!=0) && digits<24)
  {
                     carry=a.d2%10; a.d2/=10;
    a.d1+=carry<<24; carry=a.d1%10; a.d1/=10;
    a.d0+=carry<<24; carry=a.d0%10; a.d0/=10;
    digit[digits++]=carry;
  }
  if(digits==0)sprintf(buf,"0");
  else
  {
    digits--;
    while(digits >= 0)
    {
      sprintf(&(buf[i++]),"%1d",digit[digits--]);
    }
  }
}


void print_dez144(int144 a, char *buf)
{
/*
writes "a" into "buf" in decimal
"buf" must be at least 45 bytes
*/
  char digit[44];
  int digits=0,carry,i=0;
  
  while((a.d0!=0 || a.d1!=0 || a.d2!=0 || a.d3!=0 || a.d4!=0 || a.d5!=0) && digits<44)
  {
                     carry=a.d5%10; a.d5/=10;
    a.d4+=carry<<24; carry=a.d4%10; a.d4/=10;
    a.d3+=carry<<24; carry=a.d3%10; a.d3/=10;
    a.d2+=carry<<24; carry=a.d2%10; a.d2/=10;
    a.d1+=carry<<24; carry=a.d1%10; a.d1/=10;
    a.d0+=carry<<24; carry=a.d0%10; a.d0/=10;
    digit[digits++]=carry;
  }
  if(digits==0)sprintf(buf,"0 bla");
  else
  {
    digits--;
    while(digits >= 0)
    {
      sprintf(&(buf[i++]),"%1d",digit[digits--]);
    }
  }
}

void print_dez96(unsigned int a_hi, unsigned int a_mid, unsigned int a_lo, char *buf)
/*
writes "a" into "buf" in decimal
"buf" must be at least 30 bytes
*/
{
  char digit[29];
  int  digits=0,carry,i=0;
  long long int tmp;
  
  while((a_lo!=0 || a_mid!=0 || a_hi!=0) && digits<29)
  {
                                                    carry=a_hi%10; a_hi/=10;
    tmp = a_mid; tmp += (long long int)carry << 32; carry=tmp%10;  a_mid=tmp/10;
    tmp = a_lo;  tmp += (long long int)carry << 32; carry=tmp%10;  a_lo=tmp/10;
    digit[digits++]=carry;
  }
  if(digits==0)sprintf(buf,"0");
  else
  {
    digits--;
    while(digits >= 0)
    {
      sprintf(&(buf[i++]),"%1d",digit[digits--]);
    }
  }
}


int tf_class_71(unsigned int exp, int bit_min, unsigned long long int k_min, unsigned long long int k_max, mystuff_t *mystuff)
{
  return 0;
}
int tf_class_75(unsigned int exp, int bit_min, unsigned long long int k_min, unsigned long long int k_max, mystuff_t *mystuff)
{
  return 0;
}
int tf_class_barrett79(unsigned int exp, int bit_min, unsigned long long int k_min, unsigned long long int k_max, mystuff_t *mystuff)
{
  return 0;
}
int tf_class_barrett92(unsigned int exp, int bit_min, unsigned long long int k_min, unsigned long long int k_max, mystuff_t *mystuff)
{
  return 0;
}
int tf_class_95(unsigned int exp, int bit_min, unsigned long long int k_min, unsigned long long int k_max, mystuff_t *mystuff)
{
  return 0;
}
int tf_class_opencl(unsigned int exp, int bit_min, unsigned long long int k_min, unsigned long long int k_max, mystuff_t *mystuff, enum GPUKernels use_kernel)
{
  size_t size = mystuff->threads_per_grid * sizeof(int);
  int i, stream = 0, status, wait = 0;
  struct timeval timer, timer2;
  unsigned long long int twait=0, eta;
  unsigned int cwait=0;
// for TF_72BIT  
  int72  k_base;
  int144 b_preinit = {0};

  unsigned int factor_lo, factor_mid, factor_hi;
  unsigned long long int b_preinit_lo, b_preinit_mid, b_preinit_hi;
  int shiftcount,ln2b,count=1;
  unsigned long long int k_diff;
  unsigned long long int t;
  char string[50];
  int factorsfound=0, running=0;
  FILE *resultfile;
  
  int h_ktab_index = 0;
  unsigned long long int k_min_grid[NUM_STREAMS_MAX];	// k_min_grid[N] contains the k_min for h_ktab[N], only valid for preprocessed h_ktab[]s
  
  timer_init(&timer);
#ifdef DETAILED_INFO
  printf("tf_class_opencl(%u, %d, %" PRIu64 ", %" PRIu64 ", ...)\n",exp, bit_min, k_min, k_max);
#endif

  new_class=1; // tell run_kernel to re-submit the one-time kernel arguments
  if ( k_max < k_min) k_max = k_min + 1;  // otherwise it would skip small bit ranges

  /* set result array to 0 */ 
  memset(mystuff->h_RES,0,32 * sizeof(int));
  status = clEnqueueWriteBuffer(commandQueue,
                mystuff->d_RES,
                CL_FALSE,          // Don't wait for completion; it's fast to copy 128 bytes ;-)
                0,
                32 * sizeof(int),
                mystuff->h_RES,
                0,
                NULL,
                &mystuff->copy_events[0]);
  if(status != CL_SUCCESS) 
	{  
		std::cout<<"Error " << status << ": Copying h_RES(clEnqueueWriteBuffer)\n";
		return RET_ERROR; // # factors found ;-)
	}

  for(i=0; i<mystuff->num_streams; i++)
  {
    mystuff->stream_status[i] = UNUSED;
    k_min_grid[i] = 0;
  }
  
  shiftcount=10;  // no exp below 2^10 ;-)
  while((1ULL<<shiftcount) < (unsigned long long int)exp)shiftcount++;
#ifdef DETAILED_INFO
  printf("bits in exp %u: %u, ", exp, shiftcount);
#endif
  shiftcount--;ln2b=1;
  if(bit_min < 64) count=2; // allow for lesser preprocessing if factors are small

  do
  {
    shiftcount--;
    ln2b<<=1;
    if(exp&(1<<(shiftcount)))ln2b++;
  }
  while (count*ln2b < kernel_info[use_kernel].bit_max);
#ifdef DETAILED_INFO
  printf("remaining shiftcount = %d, ln2b = %d\n", shiftcount, ln2b);
#endif
  b_preinit_hi=0;b_preinit_mid=0;b_preinit_lo=0;
  count=0;
  if (use_kernel == _71BIT_MUL24)
  {
    if     (ln2b<24 )b_preinit.d0=1<< ln2b;       // should not happen
    else if(ln2b<48 )b_preinit.d1=1<<(ln2b-24);   // should not happen
    else if(ln2b<72 )b_preinit.d2=1<<(ln2b-48);
    else if(ln2b<96 )b_preinit.d3=1<<(ln2b-72);
    else if(ln2b<120)b_preinit.d4=1<<(ln2b-96);
    else             b_preinit.d5=1<<(ln2b-120);	// b_preinit = 2^ln2b
  }
  else
  {
    --shiftcount;  // an adjustment the kernel would have to do otherwise - or not (Barrett?) TODO
    if     (ln2b<64 )b_preinit_lo = 1ULL<< ln2b;
    else if(ln2b<128)b_preinit_mid= 1ULL<<(ln2b-64);
    else             b_preinit_hi = 1ULL<<(ln2b-128); // b_preinit = 2^ln2b
  }

  // combine for more efficient passing of parameters
  cl_ulong4 b_preinit4 = {b_preinit_lo, b_preinit_mid, b_preinit_hi, shiftcount};

#ifdef VERBOSE_TIMING
  printf("mfakt(%u,...) init:     %" PRIu64 "msec\n",exp,timer_diff(&timer)/1000);
#endif

  status = clWaitForEvents(1, &mystuff->copy_events[0]); // copying RES finished?
  if(status != CL_SUCCESS) 
  { 
	  std::cerr<< "Error " << status << ": Waiting for copy RES call to finish. (clWaitForEvents)\n";
	  return RET_ERROR;
  }

  while((k_min <= k_max) || (running > 0))
  {
    h_ktab_index = count % mystuff->num_streams;
#ifdef VERBOSE_TIMING
    printf("##### k_start = %" PRIu64 " ##### ",k_min);
    printf("mfakt(%u,...) start:    %" PRIu64 "msec\n",exp,timer_diff(&timer)/1000);
#endif

/* preprocessing: calculate a ktab (factor table) */
    if((mystuff->stream_status[h_ktab_index] == UNUSED) && (k_min <= k_max))	// if we have an empty h_ktab we can preprocess another one
    {
#ifdef DEBUG_STREAM_SCHEDULE
      printf(" STREAM_SCHEDULE: preprocessing on h_ktab[%d]\n", h_ktab_index);
#endif
    
      sieve_candidates(mystuff->threads_per_grid, mystuff->h_ktab[h_ktab_index], mystuff->sieve_primes);
      k_diff=mystuff->h_ktab[h_ktab_index][mystuff->threads_per_grid-1]+1;
      k_diff*=NUM_CLASSES;				/* NUM_CLASSES because classes are mod NUM_CLASSES */
      
      k_min_grid[h_ktab_index] = k_min;
      /* try upload ktab*/

      /// test test test
      // mystuff->h_ktab[h_ktab_index][0]=0;
      /////////
      status = clEnqueueWriteBuffer(commandQueue,
                mystuff->d_ktab[h_ktab_index],
                CL_FALSE,
                0,
                size,
                mystuff->h_ktab[h_ktab_index],
                0,
                NULL,
                &mystuff->copy_events[h_ktab_index]);

      if(status != CL_SUCCESS) 
	    {  
	        std::cout<<"Error " << status << ": Copying h_ktab(clEnqueueWriteBuffer)\n";
          return RET_ERROR; // # factors found ;-)
	    }
	    mystuff->stream_status[h_ktab_index] = PREPARED;
      running++;
#ifdef DEBUG_STREAM_SCHEDULE
      printf("k-base: %llu, ", k_min);
      print1DArray("ktab", mystuff->h_ktab[h_ktab_index], mystuff->threads_per_grid);
#endif

#ifdef VERBOSE_TIMING
      printf("mfakt(%u,...) sieved:  %" PRIu64 "msec\n",exp,timer_diff(&timer)/1000);
#endif
      count++;
      k_min += (unsigned long long int)k_diff;
    }

    wait = 1;

    for(i=0; i<mystuff->num_streams; i++)
    {
      switch (mystuff->stream_status[i])
      {
        case UNUSED:   if (k_min <= k_max) wait = 0; break;  // still some work to do
        case PREPARED:                   // start the calculation of a preprocessed dataset on the device
          {
            if (use_kernel == _71BIT_MUL24)
            {
              k_base.d0 =  k_min_grid[i] & 0xFFFFFF;
              k_base.d1 = (k_min_grid[i] >> 24) & 0xFFFFFF;
              k_base.d2 =  k_min_grid[i] >> 48;
              run_kernel24(kernel_info[use_kernel].kernel, exp, k_base, i, b_preinit, mystuff->d_RES, shiftcount);
            }
            else 
            {
              run_kernel64(kernel_info[use_kernel].kernel, exp, k_min_grid[i], i, b_preinit4, mystuff->d_RES, bit_min-63);
            }
#ifdef DEBUG_STREAM_SCHEDULE
            printf(" STREAM_SCHEDULE: started GPU kernel using h_ktab[%d] (%s, %u, %u, ...)\n", i, kernel_info[use_kernel].kernelname, exp, k_min_grid[i]);
#endif
            mystuff->stream_status[i] = RUNNING;
            break;
          }
        case RUNNING:                    // check if it really is still running
          {
            cl_int event_status;
            status = clGetEventInfo(mystuff->exec_events[i],
                         CL_EVENT_COMMAND_EXECUTION_STATUS,
                         sizeof(cl_int),
                         &event_status,
                         NULL);
#ifdef DEBUG_STREAM_SCHEDULE
	          std::cout<<  " STREAM_SCHEDULE: Querying event " << i << " = " << event_status << "\n";
#endif
            if(status != CL_SUCCESS) 
            { 
	            std::cerr<< "Error " << status << ": Querying event " << i << ". (clGetEventInfo)\n";
	    	      return RET_ERROR;
            }
            if (event_status > CL_COMPLETE) /* still running: CL_QUEUED=3 (command has been enqueued in the command-queue),
                                               CL_SUBMITTED=2 (enqueued command has been submitted by the host to the device associated with the command-queue),
                                               CL_RUNNING=1 (device is currently executing this command), CL_COMPLETE=0 */
            {
              break;
            }
            else // finished
            {
#ifdef CL_PERFORMANCE_INFO
              cl_ulong startTime;
              cl_ulong endTime;
              /* Get kernel profiling info */
              status = clGetEventProfilingInfo(mystuff->copy_events[i],
                                CL_PROFILING_COMMAND_START,
                                sizeof(cl_ulong),
                                &startTime,
                                0);
              if(status != CL_SUCCESS)
 	            { 
		            std::cerr<< "Error " << status << " in clGetEventProfilingInfo.(startTime)\n";
                return 1;
              }
              status = clGetEventProfilingInfo(mystuff->copy_events[i],
                                CL_PROFILING_COMMAND_END,
                                sizeof(cl_ulong),
                                &endTime,
                                0);
              if(status != CL_SUCCESS)
 	            { 
		            std::cerr<< "Error " << status << " in clGetEventProfilingInfo.(endTime)\n";
                return 1;
              }
              std::cout<< mystuff->threads_per_grid << " candidates copied in " << (endTime - startTime)/1e3 << " us ("
                       << size * 1e3 / (endTime - startTime) << "MB/s), " ;
              status = clGetEventProfilingInfo(mystuff->exec_events[i],
                                CL_PROFILING_COMMAND_START,
                                sizeof(cl_ulong),
                                &startTime,
                                0);
              if(status != CL_SUCCESS)
 	            { 
		            std::cerr<< "Error " << status << " in clGetEventProfilingInfo.(startTime)\n";
                return 1;
              }
              status = clGetEventProfilingInfo(mystuff->exec_events[i],
                                CL_PROFILING_COMMAND_END,
                                sizeof(cl_ulong),
                                &endTime,
                                0);
              if(status != CL_SUCCESS)
 	            { 
		            std::cerr<< "Error " << status << " in clGetEventProfilingInfo.(endTime)\n";
                return 1;
              }
              std::cout<< "processed in " << (endTime - startTime)/1e6 << " ms (" << double(mystuff->threads_per_grid) *1e3/ (endTime - startTime) << " M/s)\n";
#endif
              status = clReleaseEvent(mystuff->exec_events[i]);
              if(status != CL_SUCCESS) 
              { 
		         	  std::cerr<< "Error " << status << ": Release exec event object. (clReleaseEvent)\n";
		         	  return RET_ERROR;
    	       	}
              status = clReleaseEvent(mystuff->copy_events[i]);
             	if(status != CL_SUCCESS) 
           	  { 
		          	std::cerr<< "Error " << status << ": Release copy event object. (clReleaseEvent)\n";
		         	  return RET_ERROR;
            	}

              if (event_status < CL_COMPLETE) // error
              {
	              std::cerr<< "Error " << event_status << " during execution of block " << count << " in h_ktab[" << i << "]\n";
	    	        return RET_ERROR;
              }
              else
              {
                mystuff->stream_status[i] = DONE;
                /* no break to fall through to process the DONE value */
              }
            }
          }
        case DONE:                       // get the results
          {                              // or maybe not; wait until the class is done.
            mystuff->stream_status[i] = UNUSED;
            --running;
            if ((k_min <= k_max) || (running==0)) wait = 0;  // some k's left to be processed, or nothing running on GPU - not time to sleep!
            break;
          }
      }
    }

    if(wait > 0)
    {
      /* no unused h_ktab for preprocessing. 
      This usually means that
      a) all GPU streams are busy 
      or
      b) we're at the and of the class
      so let's wait for the stream that was scheduled first, or any other busy one */
      timer_init(&timer2);

      i = (count - running) % mystuff->num_streams; // the oldest still running stream
      if (mystuff->stream_status[i] != RUNNING)     // if that one is not running, take the first running one
      {
        for(i=0; (mystuff->stream_status[i] != RUNNING) && (i<mystuff->num_streams); i++) ;
      }
      if(i<mystuff->num_streams)
      {
#ifdef DEBUG_STREAM_SCHEDULE
        printf(" STREAM_SCHEDULE: Wait for stream %d\n", i);
#endif
        status = clWaitForEvents(1, &mystuff->exec_events[i]); // wait for completion
        if(status != CL_SUCCESS) 
        { 
	        std::cerr<< "Error " << status << ": Waiting for kernel call to finish. (clWaitForEvents)\n";
	      	return RET_ERROR;
        }
      }
      else
      {
#ifdef DEBUG_STREAM_SCHEDULE
        printf(" STREAM_SCHEDULE: Tried to wait but nothing is running!\n");
#endif
        running = 0; /* if nothing is running, correct this if necessary */
      }
      twait+=timer_diff(&timer2);
      cwait++;
      // technically the stream we've waited for is finished, but
      // leave the stream in status RUNNING to let the case-loop above check for errors and do cleanup
    }
  }
  // all done?

  for(i=0; i<mystuff->num_streams; i++)
  {
    if (mystuff->stream_status[i] != UNUSED)
    { // should not happen
      std::cerr << "Block " << count -i << ", k_min=" << k_min_grid[i] << " in h_ktab[" << i << "] not yet complete!\n";
    }
  }


#ifdef VERBOSE_TIMING
  printf("mfakt(%u,...) wait:     %" PRIu64 "msec ",exp,timer_diff(&timer)/1000);
  printf("##### k_end = %" PRIu64 " #####\n",k_min);
#endif    

  status = clEnqueueReadBuffer(commandQueue,
                mystuff->d_RES,
                CL_TRUE,
                0,
                32 * sizeof(int),
                mystuff->h_RES,
                0,
                NULL,
                NULL);
    
  if(status != CL_SUCCESS) 
	{ 
    std::cout << "Error " << status << ": clEnqueueReadBuffer RES failed. (clEnqueueReadBuffer)\n";
		return 1;
  }

#ifdef DETAILED_INFO
  print1DArray("RES", mystuff->h_RES, 32);
#endif

#ifdef VERBOSE_TIMING
  printf("mfakt(%u,...) download: %" PRIu64 "msec\n",exp,timer_diff(&timer)/1000);
#endif

  t=timer_diff(&timer)/1000;
  if(t==0)t=1;	/* prevent division by zero in the following printf(s) */

  if(mystuff->mode != MODE_SELFTEST_SHORT)
  {
    printf("%4" PRIu64 "/%4d", k_min%NUM_CLASSES, (int)NUM_CLASSES);

    if(((unsigned long long int)mystuff->threads_per_grid * (unsigned long long int)count) < 1000000000ULL)
      printf(" | %9.2fM", (double)mystuff->threads_per_grid * (double)count / 1000000.0);
    else
      printf(" | %9.2fG", (double)mystuff->threads_per_grid * (double)count / 1000000000.0);

         if(t < 100000ULL  )printf(" | %6.3fs", (double)t/1000.0);
    else if(t < 1000000ULL )printf(" | %6.2fs", (double)t/1000.0);
    else if(t < 10000000ULL)printf(" | %6.1fs", (double)t/1000.0);
    else                    printf(" | %6.0fs", (double)t/1000.0);

    printf(" | %6.2fM/s", (double)mystuff->threads_per_grid * (double)count / ((double)t * 1000.0));
    
    printf(" | %11d", mystuff->sieve_primes);
 
    if(mystuff->mode == MODE_NORMAL)
    {
      if(t > 250.0)
      {
        
#ifdef MORE_CLASSES      
        eta = (t * (960 - mystuff->class_counter) + 500)  / 1000;
#else
        eta = (t * (96 - mystuff->class_counter) + 500)  / 1000;
#endif
             if(eta < 3600) printf(" | %2" PRIu64 "m%02" PRIu64 "s", eta / 60, eta % 60);
        else if(eta < 86400)printf(" | %2" PRIu64 "h%02" PRIu64 "m", eta / 3600, (eta / 60) % 60);
        else                printf(" | %2" PRIu64 "d%02" PRIu64 "h", eta / 86400, (eta / 3600) % 24);
      }
      else printf(" |   n.a.");
    }
    else if(mystuff->mode == MODE_SELFTEST_FULL)printf(" |   n.a.");
  }

  if(cwait>0)
  {
    twait/=cwait;
    if(mystuff->mode != MODE_SELFTEST_SHORT)printf(" | %7" PRIu64 "us", twait);
    if(mystuff->sieve_primes_adjust==1 && twait>750 && mystuff->sieve_primes < mystuff->sieve_primes_max && (mystuff->mode != MODE_SELFTEST_SHORT))
    {
      mystuff->sieve_primes *= 9;
      mystuff->sieve_primes /= 8;
      if(mystuff->sieve_primes > mystuff->sieve_primes_max) mystuff->sieve_primes = mystuff->sieve_primes_max;
//      printf("\navg. wait > 750us, increasing SievePrimes to %d",mystuff->sieve_primes);
    }
    if(mystuff->sieve_primes_adjust==1 && twait<200 && mystuff->sieve_primes > SIEVE_PRIMES_MIN && (mystuff->mode != MODE_SELFTEST_SHORT))
    {
      mystuff->sieve_primes *= 7;
      mystuff->sieve_primes /= 8;
      if(mystuff->sieve_primes < SIEVE_PRIMES_MIN) mystuff->sieve_primes = SIEVE_PRIMES_MIN;
//      printf("\navg. wait < 200us, decreasing SievePrimes to %d",mystuff->sieve_primes);
    }
  }
  else if(mystuff->mode != MODE_SELFTEST_SHORT)printf(" |      n.a.");


  if(mystuff->mode == MODE_NORMAL)
  {
    if(mystuff->printmode == 1)printf("\r");
    else printf("\n");
  }
  if(mystuff->mode == MODE_SELFTEST_FULL && mystuff->printmode == 0)
  {
    printf("\n");
  }

  factorsfound=mystuff->h_RES[0];
  for(i=0; (i<factorsfound) && (i<10); i++)
  {
    factor_hi =mystuff->h_RES[i*3 + 1];
    factor_mid=mystuff->h_RES[i*3 + 2];
    factor_lo =mystuff->h_RES[i*3 + 3];
    if (use_kernel == _71BIT_MUL24)
    {
      int72 factor={factor_lo, factor_mid, factor_hi};
      print_dez72(factor,string);
    }
    else
    {
      print_dez96(factor_hi, factor_mid, factor_lo, string);
    }
 //    if(mystuff->mode != MODE_SELFTEST_SHORT)
    {
      if(mystuff->printmode == 1 && i == 0)printf("\n");
      printf("Result[%02d]: M%u has a factor: %s\n",i,exp,string);
    }
    if(mystuff->mode == MODE_NORMAL)
    {
      resultfile=fopen("results.txt", "a");
      fprintf(resultfile,"M%u has a factor: %s\n",exp,string);
      fclose(resultfile);
    }
  }
  if(factorsfound>=10)
  {
    if(mystuff->mode != MODE_SELFTEST_SHORT)printf("M%u: %d additional factors not shown\n",exp,factorsfound-10);
    if(mystuff->mode == MODE_NORMAL)
    {
      resultfile=fopen("results.txt", "a");
      fprintf(resultfile,"M%u: %d additional factors not shown\n",exp,factorsfound-10);
      fclose(resultfile);
    }
  }
  return factorsfound;
}


/* copy of the init and test functions for troubleshooting and playing around */

void CL_test(cl_uint devnumber)
{
  cl_int status;
  size_t dev_s;
  cl_uint numplatforms, i;
  cl_platform_id platform = NULL;
  cl_platform_id* platformlist = NULL;

  status = clGetPlatformIDs(0, NULL, &numplatforms);
  if(status != CL_SUCCESS)
  {
    std::cerr << "Error " << status << ": clGetPlatformsIDs(num)\n";
  }

  if(numplatforms > 0)
  {
    platformlist = new cl_platform_id[numplatforms];
    status = clGetPlatformIDs(numplatforms, platformlist, NULL);
    if(status != CL_SUCCESS)
    {
      std::cerr << "Error " << status << ": clGetPlatformsIDs\n";
    }

    if (devnumber > 10) // platform number specified as part of -d
    {
      i = devnumber/10 - 1;
      if (i < numplatforms)
      {
        platform = platformlist[i];
        char buf[128];
        status = clGetPlatformInfo(platform, CL_PLATFORM_VENDOR,
                        sizeof(buf), buf, NULL);
        if(status != CL_SUCCESS)
        {
          std::cerr << "Error " << status << ": clGetPlatformInfo(VENDOR)\n";
        }
        std::cout << "OpenCL Platform " << i+1 << "/" << numplatforms << ": " << buf;

        status = clGetPlatformInfo(platform, CL_PLATFORM_VERSION,
                        sizeof(buf), buf, NULL);
        if(status != CL_SUCCESS)
        {
          std::cerr << "Error " << status << ": clGetPlatformInfo(VERSION)\n";
        }
        std::cout << ", Version: " << buf << std::endl;
      }
      else
      {
        fprintf(stderr, "Error: Only %d platforms found. Cannot use platform %d (bad parameter to option -d).\n", numplatforms, i);
      }
    }
    else for(i=0; i < numplatforms; i++) // autoselect: search for AMD
    {
      char buf[128];
      status = clGetPlatformInfo(platformlist[i], CL_PLATFORM_VENDOR,
                        sizeof(buf), buf, NULL);
      if(status != CL_SUCCESS)
      {
        std::cerr << "Error " << status << ": clGetPlatformInfo(VENDOR)\n";
      }
      if(strncmp(buf, "Advanced Micro Devices, Inc.", sizeof(buf)) == 0)
      {
        platform = platformlist[i];
      }
      std::cout << "OpenCL Platform " << i+1 << "/" << numplatforms << ": " << buf;

      status = clGetPlatformInfo(platformlist[i], CL_PLATFORM_VERSION,
                        sizeof(buf), buf, NULL);
      if(status != CL_SUCCESS)
      {
        std::cerr << "Error " << status << ": clGetPlatformInfo(VERSION)\n";
      }
      std::cout << ", Version: " << buf << std::endl;
    }
  }

  delete[] platformlist;
  
  if(platform == NULL)
  {
    std::cerr << "Error: No platform found\n";
  }

  cl_context_properties cps[3] = { CL_CONTEXT_PLATFORM, (cl_context_properties)platform, 0 };
  context = clCreateContextFromType(cps, CL_DEVICE_TYPE_GPU, NULL, NULL, &status);
  if (status == CL_DEVICE_NOT_FOUND)
  {
    clReleaseContext(context);
    std::cout << "GPU not found, fallback to CPU." << std::endl;
    context = clCreateContextFromType(cps, CL_DEVICE_TYPE_CPU, NULL, NULL, &status);
    if(status != CL_SUCCESS) 
  	{  
   	  std::cerr << "Error " << status << ": clCreateContextFromType(CPU)\n";
    }
  }
  else if(status != CL_SUCCESS) 
	{  
		std::cerr << "Error " << status << ": clCreateContextFromType(GPU)\n";
  }

  cl_uint num_devices;
  status = clGetContextInfo(context, CL_CONTEXT_NUM_DEVICES, sizeof(num_devices), &num_devices, NULL);
  if(status != CL_SUCCESS) 
	{ 
		std::cerr << "Error " << status << ": clGetContextInfo(CL_CONTEXT_NUM_DEVICES) - assuming one device\n";
    num_devices = 1;
	}

  status = clGetContextInfo(context, CL_CONTEXT_DEVICES, 0, NULL, &dev_s);
  if(status != CL_SUCCESS) 
	{  
		std::cerr << "Error " << status << ": clGetContextInfo(numdevs)\n";
	}

	if(dev_s == 0)
	{
		std::cerr << "Error: no devices.\n";
	}

  devices = (cl_device_id *)malloc(dev_s*sizeof(cl_device_id));  // *sizeof(...) should not be needed (dev_s is in bytes)
	if(devices == 0)
	{
		std::cerr << "Error: Out of memory.\n";
	}

  status = clGetContextInfo(context, CL_CONTEXT_DEVICES, dev_s*sizeof(cl_device_id), devices, NULL);
  if(status != CL_SUCCESS) 
	{ 
		std::cerr << "Error " << status << ": clGetContextInfo(devices)\n";
	}

  devnumber = devnumber % 10;  // use only the last digit as device number, counting from 1
  cl_uint dev_from=0, dev_to=num_devices;
  if (devnumber > 0)
  {
    if (devnumber > num_devices)
    {
      fprintf(stderr, "Error: Only %d devices found. Cannot use device %d (bad parameter to option -d).\n", num_devices, devnumber);
    }
    else
    {
      dev_to    = devnumber;    // tweak the loop to run only once for our device
      dev_from  = --devnumber;  // index from 0
    }
  }
   
  for (i=dev_from; i<dev_to; i++)
  {

    status = clGetDeviceInfo(devices[i], CL_DEVICE_NAME, sizeof(deviceinfo.d_name), deviceinfo.d_name, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_NAME)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_VERSION, sizeof(deviceinfo.d_ver), deviceinfo.d_ver, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_VERSION)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_VENDOR, sizeof(deviceinfo.v_name), deviceinfo.v_name, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_VENDOR)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DRIVER_VERSION, sizeof(deviceinfo.dr_version), deviceinfo.dr_version, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DRIVER_VERSION)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_EXTENSIONS, sizeof(deviceinfo.exts), deviceinfo.exts, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_EXTENSIONS)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_GLOBAL_MEM_CACHE_SIZE, sizeof(deviceinfo.gl_cache), &deviceinfo.gl_cache, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_GLOBAL_MEM_CACHE_SIZE)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_GLOBAL_MEM_SIZE, sizeof(deviceinfo.gl_mem), &deviceinfo.gl_mem, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_GLOBAL_MEM_SIZE)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_MAX_CLOCK_FREQUENCY, sizeof(deviceinfo.max_clock), &deviceinfo.max_clock, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_MAX_CLOCK_FREQUENCY)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_MAX_COMPUTE_UNITS, sizeof(deviceinfo.units), &deviceinfo.units, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_MAX_COMPUTE_UNITS)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_MAX_WORK_GROUP_SIZE, sizeof(deviceinfo.wg_size), &deviceinfo.wg_size, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_MAX_WORK_GROUP_SIZE)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS, sizeof(deviceinfo.w_dim), &deviceinfo.w_dim, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_MAX_WORK_ITEM_SIZES, sizeof(deviceinfo.wi_sizes), deviceinfo.wi_sizes, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_MAX_WORK_ITEM_SIZES)\n";
	  }
    status = clGetDeviceInfo(devices[i], CL_DEVICE_LOCAL_MEM_SIZE, sizeof(deviceinfo.l_mem), &deviceinfo.l_mem, NULL);
    if(status != CL_SUCCESS) 
	  { 
		  std::cerr << "Error " << status << ": clGetContextInfo(CL_DEVICE_LOCAL_MEM_SIZE)\n";
	  }
    
    std::cout << "Device " << i+1  << "/" << num_devices << ": " << deviceinfo.d_name << " (" << deviceinfo.v_name << "),\ndevice version: "
      << deviceinfo.d_ver << ", driver version: " << deviceinfo.dr_version << "\nExtensions: " << deviceinfo.exts
      << "\nGlobal memory:" << deviceinfo.gl_mem << ", Global memory cache: " << deviceinfo.gl_cache
      << ", local memory: " << deviceinfo.l_mem << ", workgroup size: " << deviceinfo.wg_size << ", Work dimensions: " << deviceinfo.w_dim
      << "[" << deviceinfo.wi_sizes[0] << ", " << deviceinfo.wi_sizes[1] << ", " << deviceinfo.wi_sizes[2] << ", " << deviceinfo.wi_sizes[3] << ", " << deviceinfo.wi_sizes[4]
      << "] , Max clock speed:" << deviceinfo.max_clock << ", compute units:" << deviceinfo.units << std::endl;
  }

  deviceinfo.maxThreadsPerBlock = deviceinfo.wi_sizes[0];
  deviceinfo.maxThreadsPerGrid  = deviceinfo.wi_sizes[0];
  for (i=1; i<deviceinfo.w_dim && i<5; i++)
  {
    if (deviceinfo.wi_sizes[i])
      deviceinfo.maxThreadsPerGrid *= deviceinfo.wi_sizes[i];
  }

//  cl_command_queue_properties props = 0;
  cl_command_queue_properties props = CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE;  // kernels and copy-jobs are queued with event dependencies, so this should work ...
  props |= CL_QUEUE_PROFILING_ENABLE;

  commandQueue = clCreateCommandQueue(context, devices[devnumber], props, &status);
  if(status != CL_SUCCESS) 
	{ 
    std::cerr << "Error " << status << ": clCreateCommandQueue(dev#" << devnumber+1 << ")\n";
	}

	size_t size;
	char*  source;

	std::fstream f(KERNEL_FILE, (std::fstream::in | std::fstream::binary));

	if(f.is_open())
	{
		f.seekg(0, std::fstream::end);
		size = (size_t)f.tellg();
		f.seekg(0, std::fstream::beg);

		source = (char *) malloc(size+1);
		if(!source)
		{
			f.close();
      std::cerr << "\noom\n";
		}

		f.read(source, size);
		f.close();
		source[size] = '\0';
  }
	else
	{
		std::cerr << "\nKernel file ""KERNEL_FILE"" not found, it needs to be in the same directory as the executable.\n";
	}

  program = clCreateProgramWithSource(context, 1, (const char **)&source, &size, &status);
	if(status != CL_SUCCESS) 
	{ 
	  std::cerr << "Error " << status << ": clCreateProgramWithSource\n";
	}

  status = clBuildProgram(program, 1, &devices[devnumber], "-Werror -O3", NULL, NULL);
  if(status != CL_SUCCESS) 
  { 
    if(status == CL_BUILD_PROGRAM_FAILURE)
    {
      cl_int logstatus;
      char *buildLog = NULL;
      size_t buildLogSize = 0;
      logstatus = clGetProgramBuildInfo (program, devices[devnumber], CL_PROGRAM_BUILD_LOG, 
                buildLogSize, buildLog, &buildLogSize);
      if(logstatus != CL_SUCCESS)
      {
        std::cerr << "Error " << logstatus << ": clGetProgramBuildInfo failed.";
      }
      buildLog = (char*)calloc(buildLogSize,1);
      if(buildLog == NULL)
      {
        std::cerr << "\noom\n";
      }

      logstatus = clGetProgramBuildInfo (program, devices[devnumber], CL_PROGRAM_BUILD_LOG, 
                buildLogSize, buildLog, NULL);
      if(logstatus != CL_SUCCESS)
      {
        std::cerr << "Error " << logstatus << ": clGetProgramBuildInfo failed.";
        free(buildLog);
      }

      std::cout << " \n\tBUILD OUTPUT\n";
      std::cout << buildLog << std::endl;
      std::cout << " \tEND OF BUILD OUTPUT\n";
      free(buildLog);
    }
		std::cerr<<"Error " << status << ": clBuildProgram\n";
  }

  free(source);  

  /* get kernel by name */
  kernel_info[_64BIT_64_OpenCL].kernel = clCreateKernel(program, kernel_info[_64BIT_64_OpenCL].kernelname, &status);
  if(status != CL_SUCCESS) 
	{  
		std::cerr<<"Error " << status << ": Creating Kernel mfakto_cl_64 from program. (clCreateKernel)\n";
	}

  kernel_info[BARRETT92_64_OpenCL].kernel = clCreateKernel(program, kernel_info[BARRETT92_64_OpenCL].kernelname, &status);
  if(status != CL_SUCCESS) 
	{  
		std::cerr<<"Error " << status << ": Creating Kernel mfakt_cl_barrett92 from program. (clCreateKernel)\n";
	}

  kernel_info[_TEST_MOD_].kernel = clCreateKernel(program, kernel_info[_TEST_MOD_].kernelname, &status);
  if(status != CL_SUCCESS) 
	{  
		std::cerr<<"Error " << status << ": Creating Kernel mod_128_64_k from program. (clCreateKernel)\n";
	}

  kernel_info[_95BIT_64_OpenCL].kernel = clCreateKernel(program, kernel_info[_95BIT_64_OpenCL].kernelname, &status);
  if(status != CL_SUCCESS) 
	{  
		std::cerr<<"Error " << status << ": Creating Kernel mfakto_cl_95 from program. (clCreateKernel)\n";
	}

  /* init_streams */

  mystuff.threads_per_grid = 1024 * 1024;
  
  if (context==NULL)
  {
    fprintf(stderr, "invalid context.\n");
  }

  for(i=0;i<(mystuff.num_streams);i++)
  {
    mystuff.stream_status[i] = UNUSED;
    if( (mystuff.h_ktab[i] = (unsigned int *) malloc( mystuff.threads_per_grid * sizeof(int))) == NULL )
    {
      printf("ERROR: malloc(h_ktab[%d]) failed\n", i);
    }
    mystuff.d_ktab[i] = clCreateBuffer(context, 
                      CL_MEM_READ_ONLY | CL_MEM_USE_HOST_PTR,
                      mystuff.threads_per_grid * sizeof(int),
                      mystuff.h_ktab[i], 
                      &status);
    if(status != CL_SUCCESS) 
  	{ 
	  	std::cout<<"Error " << status << ": clCreateBuffer (h_ktab[" << i << "]) \n";
	  }
  }
  if( (mystuff.h_RES = (unsigned int *) malloc(32 * sizeof(int))) == NULL )
  {
    printf("ERROR: malloc(h_RES) failed\n");
  }
  mystuff.d_RES = clCreateBuffer(context,
                    CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR,
                    32 * sizeof(int),
                    mystuff.h_RES,
                    &status);
  if(status != CL_SUCCESS) 
  { 
		std::cout<<"Error " << status << ": clCreateBuffer (d_RES)\n";
	}


  // Now, quickly test one kernel ...
  // (10 * 2^64+25) mod 3 * 2^23
  cl_ulong hi=10;
  cl_ulong lo=25;
  cl_ulong q=3<<23;
  cl_float qr=0.9998f/(cl_float)q;
  cl_ulong res_hi;
  cl_ulong res_lo;

  cl_event mod_evt;

  res_hi = res_lo = 0;

  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    0, 
                    sizeof(cl_ulong), 
                    (void *)&hi);
  if(status != CL_SUCCESS) 
	{ 
		std::cout<<"Error " << status << ": Setting kernel argument. (hi)\n";
	}
  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    1, 
                    sizeof(cl_ulong), 
                    (void *)&lo);
  if(status != CL_SUCCESS) 
	{ 
		std::cout<<"Error " << status << ": Setting kernel argument. (lo)\n";
	}
  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    2, 
                    sizeof(cl_ulong), 
                    (void *)&q);
  if(status != CL_SUCCESS) 
	{ 
		std::cout<<"Error " << status << ": Setting kernel argument. (q)\n";
	}
  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    3, 
                    sizeof(cl_float), 
                    (void *)&qr);
  if(status != CL_SUCCESS) 
	{ 
		std::cout<<"Error " << status << ": Setting kernel argument. (qr)\n";
	}
  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    4, 
                    sizeof(cl_mem), 
                    (void *)&mystuff.d_RES);
  if(status != CL_SUCCESS) 
	{ 
		std::cout<<"Error " << status << ": Setting kernel argument. (RES)\n";
	}
  // dummy arg if KERNEL_TRACE is enabled: ignore errors if not.
  status = clSetKernelArg(kernel_info[_TEST_MOD_].kernel, 
                    5, 
                    sizeof(cl_uint), 
                    (void *)&status);

  struct timeval timer;
  cl_ulong startTime, endTime;

  timer_init(&timer);
#define TEST_LOOPS 10

  for (i=0; i<TEST_LOOPS; i++)
  {
    status = clEnqueueTask(commandQueue,
                 kernel_info[_TEST_MOD_].kernel,
                 0,
                 NULL,
                 &mod_evt);
    if(status != CL_SUCCESS) 
  	{ 
  		std::cerr<< "Error " << status << ": Enqueueing kernel(clEnqueueTask)\n";
  	}
    try {

    status = clWaitForEvents(1, &mod_evt); 
    } catch(...) {
      std::cerr << "Exception in clWaitForEvents\n";
    }
    if(status != CL_SUCCESS) 
    { 
  	  std::cerr<< "Error " << status << ": Waiting for mod call to finish. (clWaitForEvents)\n";
    }

              /* Get kernel profiling info */
              status = clGetEventProfilingInfo(mod_evt,
                                CL_PROFILING_COMMAND_START,
                                sizeof(cl_ulong),
                                &startTime,
                                0);
              if(status != CL_SUCCESS)
 	            { 
		            std::cerr<< "Error " << status << " in clGetEventProfilingInfo.(startTime)\n";
              }
              status = clGetEventProfilingInfo(mod_evt,
                                CL_PROFILING_COMMAND_END,
                                sizeof(cl_ulong),
                                &endTime,
                                0);
              if(status != CL_SUCCESS)
 	            { 
		            std::cerr<< "Error " << status << " in clGetEventProfilingInfo.(endTime)\n";
              }
              std::cout<< "mod_kernel finished in " << (endTime - startTime)/1e3 << " us.\n" ;

    status = clReleaseEvent(mod_evt);
    if(status != CL_SUCCESS) 
    { 
	  	std::cerr<< "Error " << status << ": Release mod event object. (clReleaseEvent)\n";
    }
  }

  std::cout << "Avg. test kernel runtime (incl. overhead): " << timer_diff(&timer)/TEST_LOOPS << " us.\n";

  status = clEnqueueReadBuffer(commandQueue,
                mystuff.d_RES,
                CL_TRUE,
                0,
                32 * sizeof(int),
                mystuff.h_RES,
                0,
                NULL,
                NULL);
    
  if(status != CL_SUCCESS) 
	{ 
    std::cerr << "Error " << status << ": clEnqueueReadBuffer RES failed. (clEnqueueReadBuffer)\n";
  }
  res_hi = mystuff.h_RES[0];
  res_lo = mystuff.h_RES[1];


  printf("res-mod: %llx:%llx mod %llx = %llx:%llx\n", hi, lo, q, res_hi, res_lo);


}
