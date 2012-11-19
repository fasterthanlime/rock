import io/File
import structs/[List, ArrayList]
import ../[BuildParams, Target]
import ../../middle/Module
import ../../backend/cnaughty/CGenerator
import Driver

/**
    Combine driver, which compiles all .c files in one pass.

    Use it with -driver=combine

    This may be faster for very small projects if for some reason
    lib-caching doesn't work for you, but in general you're
    better off with SequenceDriver + libcaching (on by default).

    The combine driver is definitely a bad choice for large projects
    before gcc sometimes gets mixed up with large files, it yields errors
    that aren't there with a sequence compilation (ie. SequenceDriver)

    :author: Amos Wenger (nddrylliog)
 */
CombineDriver: class extends Driver {

    init: func (.params) { super(params) }

    compile: func (module: Module) -> Int {

        params outPath mkdirs()
        for(candidate in module collectDeps()) {
            CGenerator new(params, candidate) write()
        }

        params compiler reset()

        copyLocalHeaders(module, params, ArrayList<Module> new())

        if(params debug) params compiler setDebugEnabled()      
        params compiler addIncludePath(File new(params distLocation, "libs/headers/") getPath())
        params compiler addIncludePath(params outPath getPath())
        addDeps(module, ArrayList<Module> new(), ArrayList<String> new())

        for(define in params defines) {
			params compiler defineSymbol(define)
		}
        for(dynamicLib in params dynamicLibs) {
            params compiler addDynamicLibrary(dynamicLib)
        }
        for(incPath in params incPath getPaths()) {
            params compiler addIncludePath(incPath getPath())
        }
        for(additional in params additionals) {
            params compiler addObjectFile(additional)
        }
        for(compilerArg in params compilerArgs) {
            params compiler addObjectFile(compilerArg)
        }

        if(params link) {
            if (params binaryPath != "") {
                params compiler setOutputPath(params binaryPath)
            } else {
                checkBinaryNameCollision(module simpleName)
                params compiler setOutputPath(module simpleName)
            }
            libs := getFlagsFromUse(module)
            for(lib in libs) {
                //printf("[CombineDriver] Adding lib %s from use\n", lib)
                params compiler addObjectFile(lib)
            }
            for(libPath in params libPath getPaths()) {
                params compiler addLibraryPath(libPath getPath())
            }

            if(params enableGC) {
                if(params dynGC) {
                    params compiler addDynamicLibrary("gc")
                } else {
                    arch := params arch equals?("") ? Target getArch() : params arch
                    libPath := "libs/" + Target toString(arch) + "/libgc.a"
                    params compiler addObjectFile(File new(params distLocation, libPath) path)
                }
                params compiler addDynamicLibrary("pthread")
            }
        } else {
            params compiler setCompileOnly()
        }

        if(params verbose) println(params compiler getCommandLine())

        code := params compiler launch()
        if(code != 0) {
            fprintf(stderr, "C compiler failed, aborting compilation process\n")
        }
        return code

    }

}
