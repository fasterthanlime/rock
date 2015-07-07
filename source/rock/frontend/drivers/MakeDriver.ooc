
// sdk stuff
import io/[File, FileWriter]
import structs/[List, ArrayList, HashMap]

// our stuff
import Driver, MetaDriver, CCompiler, Flags, SourceFolder

import rock/frontend/[BuildParams, Target]
import rock/middle/[Module, UseDef]
import rock/backend/cnaughty/CGenerator
import rock/io/TabbedWriter

/**
 * Generate the .c source files in a build/ directory, along with a
 * Makefile that allows to build a version of your program without any
 * ooc-related dependency.
 */
MakeDriver: class extends MetaDriver {
    init: func (.params) { super("Makefile", "Make driver", params) }

    getWriter: func (flags: Flags, toCompile: ArrayList<Module>, module: Module) -> MetaDriverWriter {
        MakefileWriter new(params, makefile, flags, toCompile, module, originalOutPath)
    }
}

MakefileWriter: class extends MetaDriverWriter {

    file: File
    flags: Flags
    params: BuildParams
    tw: TabbedWriter
    toCompile: ArrayList<Module>
    module: Module
    originalOutPath: File

    init: func (=params, =file, =flags, =toCompile, =module, =originalOutPath) {
        tw = TabbedWriter new(FileWriter new(file))
    }

    write: func {
        "Writing to %s" printfln(file path)
        writePrelude()
        writeCC()
        writeAR()
        writePrefix()
        writeArchDetect()
        writeThreadFlags()
        writeDebugFlags()
        writePkgConfig()
        writeFlags()
        writeExecutable()
        writeObjectFiles()
        writeMainTargets()
        writeObjectTargets()
    }

    writePrelude: func {
        tw writeln("# Makefile generated by rock, the ooc compiler written in ooc")
        tw writeln("# See https://github.com/nddrylliog/rock and http://ooc-lang.org")
        tw nl()
    }

    writeCC: func {
        tw writeln("ifeq ($(GCC),)")
        tw writeln("ifeq ($(CROSS),)")
        tw write  ("  GCC:="). write(params compiler executableName). nl()
        tw writeln("else")
        tw writeln("  GCC:=$(CROSS)-gcc")
        tw writeln("endif")
        tw writeln("endif")
        tw nl()
    }

    writeAR: func {
        tw writeln("ifeq ($(AR),)")
        tw writeln("ifeq ($(CROSS),)")
        tw write  ("  AR:="). write(params ar). nl()
        tw writeln("else")
        tw writeln("  AR:=$(CROSS)-ar")
        tw writeln("endif")
        tw writeln("endif")
        tw nl()
    }

    writePrefix: func {
        tw writeln("ifeq ($(PREFIX),)")
        tw writeln(" PREFIX:=/usr")
        tw writeln("endif")
        tw nl()
    }

    writePkgConfig: func {
        tw writeln("# pkg-config paths & dependencies")
        tw writeln("ifeq ($(PKG_CONFIG_PATH),)")
        tw writeln("  PKG_CONFIG_PATH:=$(PREFIX)/lib/pkgconfig")
        tw writeln("endif")

        tw writeln("PKG_CONFIG?=pkg-config")

        tw writeln("PKGS:=")
    }

    writeArchDetect: func {
        tw writeln("# system / arch detection")
        tw writeln("CROSS_TOKENS:=$(subst -, ,$(CROSS))")
        tw nl()

        tw writeln("# try to determine system from CROSS")
        tw writeln("ifeq ($(SYSTEM),)")
        tw writeln("  ifneq ($(strip $(filter apple,$(CROSS_TOKENS))),)")
        tw writeln("    SYSTEM:=osx")
        tw writeln("  else ifneq ($(strip $(filter mingw%,$(CROSS_TOKENS))),)")
        tw writeln("    SYSTEM:=win")
        tw writeln("  endif # cross -> system")
        tw writeln("endif # unknown system")

        tw writeln("# try to determine system from build environment")
        tw writeln("ifeq ($(SYSTEM),)")
        tw writeln("  BUILD_SYSTEM := $(shell uname -s)")
        tw writeln("  ifeq ($(BUILD_SYSTEM), Linux)")
        tw writeln("    SYSTEM=linux")
        tw writeln("  else ifeq ($(BUILD_SYSTEM), FreeBSD)")
        tw writeln("    SYSTEM=freebsd")
        tw writeln("  else ifeq ($(BUILD_SYSTEM), OpenBSD)")
        tw writeln("    SYSTEM=openbsd")
        tw writeln("  else ifeq ($(BUILD_SYSTEM), NetBSD)")
        tw writeln("    SYSTEM=netbsd")
        tw writeln("  else ifeq ($(BUILD_SYSTEM), DragonFly)")
        tw writeln("    SYSTEM=dragonfly")
        tw writeln("  else ifeq ($(BUILD_SYSTEM), Darwin)")
        tw writeln("    SYSTEM=osx")
        tw writeln("  else ifeq ($(BUILD_SYSTEM), CYGWIN_NT-5.1)")
        tw writeln("    SYSTEM=win")
        tw writeln("  else ifeq ($(BUILD_SYSTEM), MINGW32_NT-5.1)")
        tw writeln("    SYSTEM=win")
        tw writeln("  else ifeq ($(BUILD_SYSTEM), MINGW32_NT-6.1)")
        tw writeln("    SYSTEM=win")
        tw writeln("  else ifeq ($(BUILD_SYSTEM),)")
        tw writeln("    ifeq ($(OS), Windows_NT)")
        tw writeln("      SYSTEM=win")
        tw writeln("    else")
        tw writeln("      $(error \"OS $(OS) doesn't have pre-built Boehm GC packages. Please compile and install your own and recompile with GC_PATH=-lgc\")")
        tw writeln("    endif # Windows_NT")
        tw writeln("  endif # build_system -> system")
        tw writeln("endif # unknown system")
        tw nl()

        tw writeln("# try to determine arch from CROSS")
        tw writeln("ifeq ($(ARCH),)")
        tw writeln("  ifneq ($(strip $(filter x86_64,$(CROSS_TOKENS))),)")
        tw writeln("    ARCH:=64")
        tw writeln("  else ifneq ($(strip $(filter amd64,$(CROSS_TOKENS))),)")
        tw writeln("    ARCH:=64")
        tw writeln("  else ifneq ($(strip $(filter i686,$(CROSS_TOKENS))),)")
        tw writeln("    ARCH:=32")
        tw writeln("  else ifneq ($(strip $(filter i586,$(CROSS_TOKENS))),)")
        tw writeln("    ARCH:=32")
        tw writeln("  else ifneq ($(strip $(filter i486,$(CROSS_TOKENS))),)")
        tw writeln("    ARCH:=32")
        tw writeln("  else ifneq ($(strip $(filter i386,$(CROSS_TOKENS))),)")
        tw writeln("    ARCH:=32")
        tw writeln("  endif # cross -> system")
        tw writeln("endif # unknown system")

        tw writeln("# try to determine arch from build environment")
        tw writeln("ifeq ($(ARCH),)")
        tw writeln("  BUILD_MACHINE := $(shell uname -m)")
        tw writeln("  ifneq ($(TARGET), osx)")
        tw writeln("    ifeq ($(BUILD_MACHINE), x86_64)")
        tw writeln("      ARCH:=64")
        tw writeln("    else ifeq ($(PROCESSOR_ARCHITECTURE), AMD64)")
        tw writeln("      ARCH:=64")
        tw writeln("    else")
        tw writeln("      ARCH:=32")
        tw writeln("    endif")
        tw writeln("  endif # machine -> arch")
        tw writeln("endif # unknown arch")
        tw nl()

        tw writeln("TARGET:=$(SYSTEM)$(ARCH)")
        tw nl()
    }

    writeThreadFlags: func {
        tw writeln("# prepare thread flags")
        tw writeln("THREAD_FLAGS:=-pthread")
        tw writeln("ifeq ($(SYSTEM), win)")
        tw writeln(" THREAD_FLAGS:=-mthreads")
        tw writeln("endif")
        tw nl()
    }

    writeDebugFlags: func {
        tw writeln("# prepare debug flags")
        tw writeln("DEBUG_FLAGS:=")
        tw writeln("DEBUG_BUILD?=1")

        tw writeln("ifneq ($(strip $(DEBUG_BUILD)),)")
        tw writeln("  DEBUG_FLAGS+= -g")
        tw writeln("  ifeq ($(SYSTEM),osx)")
        tw writeln("    ifeq ($(CROSS),)")
        tw writeln("      # cross-compile envs typically don't support no-pie")
        tw writeln("      DEBUG_FLAGS+= -fno-pie")
        tw writeln("    endif")
        tw writeln("  else ifeq ($(SYSTEM),linux)")
        tw writeln("    ifneq ($(strip $(filter $(GCC), gcc)),)")
        tw writeln("      DEBUG_FLAGS+= -rdynamic")
        tw writeln("    endif")
        tw writeln("  endif")
        tw writeln("endif")
        tw nl()
    }

    writeFlags: func {
        tw writeln("ifeq ($(ARCH),64)")
        tw writeln("  CFLAGS+=-m64")
        tw writeln("else ifeq ($(ARCH),32)")
        tw writeln("  CFLAGS+=-m32")
        tw writeln("endif # arch -> -m option")
        tw nl()
        if(module dummy && !params staticLib){
            tw writeln("CFLAGS+=-fPIC")
            tw writeln("LDFLAGS+=-shared")
        }

        tw write("CFLAGS+= -I$(PREFIX)/include -I/usr/pkg/include $(DEBUG_FLAGS)")
        for (flag in flags compilerFlags) {
            tw write(" "). write(flag)
        }
        tw nl(). nl()

        tw write("LDFLAGS+=-L$(PREFIX)/lib -L/usr/pkg/lib")
        for(dynamicLib in params dynamicLibs) {
            tw write(" -l "). write(dynamicLib)
        }

        for(libPath in params libPath getPaths()) {
            tw write(" -L "). write(libPath getPath())
        }

        for(linkerFlag in flags linkerFlags) {
            tw write(" "). write(linkerFlag)
        }
        tw nl(). nl()

        targets := HashMap<Int, String> new()
        targets put(Target LINUX, "linux")
        targets put(Target WIN, "win")
        targets put(Target OSX, "osx")

        targets each(|target, name|
            tw write("ifeq ($(SYSTEM),"). write(name). writeln(")")
            for (useDef in flags uses) {
                writeUseDef(useDef getPropertiesForTarget(target))
            }
            tw write("endif # "). write(name). write(" usedef flags"). nl(). nl()
        )

        if(params enableGC) {
            tw writeln("LDFLAGS+=-lgc")
            tw nl()
        }
    }

    writeUseDef: func (props: UseProperties) {
        // cflags
        cflags  := ArrayList<String> new()
        for (path in props includePaths) {
            cflags add("-I" + path)
        }

        if (!cflags empty?()) {
            tw write("CFLAGS += ")
            for (flag in cflags) {
                tw write(flag). write(" ")
            }
            tw nl()
        }

        // ldflags
        ldflags := ArrayList<String> new()
        ldflags addAll(props libs)
        for (path in props libPaths) {
            ldflags add("-L" + path)
        }
        for (framework in props frameworks) {
            ldflags add("-Wl,-framework," + framework)
        }

        if (!ldflags empty?()) {
            tw write("LDFLAGS += ")
            for (flag in ldflags) {
                tw write(flag). write(" ")
            }
            tw nl()
        }

        props pkgs each(|name, value|
            tw write("PKGS+="). write(name). nl()
            tw write("CFLAGS +=$(strip $(shell PKG_CONFIG_PATH=$(PKG_CONFIG_PATH) $(PKG_CONFIG) "). write(name). write(" --cflags)) "). nl()
            tw write("LDFLAGS+=$(strip $(shell PKG_CONFIG_PATH=$(PKG_CONFIG_PATH) $(PKG_CONFIG) "). write(name). write(" --libs)) "). nl()
        )

        props customPkgs each(|customPkg|
            tw write("CFLAGS +=$(strip $(shell PATH=$(PREFIX)/bin:$PATH "). write(customPkg utilName)
            for (name in customPkg names) {
                tw write(" "). write(name)
            }
            for (arg in customPkg cflagArgs) {
                tw write(" "). write(arg)
            }
            tw write("))"). nl()

            tw write("LDFLAGS +=$(strip $(shell PATH=$(PREFIX)/bin:$PATH "). write(customPkg utilName)
            for (name in customPkg names) {
                tw write(" "). write(name)
            }
            for (arg in customPkg libsArgs) {
                tw write(" "). write(arg)
            }
            tw write("))"). nl()
        )
    }

    writeExecutable: func {
        tw writeln("ifeq ($(EXECUTABLE),)")
        tw write("EXECUTABLE:=")
        if(params binaryPath != "") {
            tw write(params binaryPath)
        } else {
            tw write(module simpleName)
        }
        tw nl()

        tw writeln("ifeq ($(SYSTEM),win)")
        if(module dummy){
            if(params staticLib){
                tw writeln("EXECUTABLE:=$(EXECUTABLE).lib")
            } else {
                tw writeln("EXECUTABLE:=$(EXECUTABLE).dll")
            }
        } else {
            tw writeln("EXECUTABLE:=$(EXECUTABLE).exe")
        }
        tw writeln("else")
        if(module dummy){
            if(params staticLib){
                tw writeln("EXECUTABLE:=$(EXECUTABLE).a")
            } else {
                tw writeln("EXECUTABLE:=$(EXECUTABLE).so")
            }
        }
        tw writeln("endif")
        tw writeln("endif # has to determine executable")
        tw nl()
    }

    writeObjectFiles: func {
        tw write("OBJECT_FILES:=")

        for (currentModule in toCompile) {
            path := File new(originalOutPath, currentModule getPath("")) getPath()
            tw write(path). write(".o ")
        }

        for (uze in flags uses) {
            // FIXME: that's no good for MakeDriver - we should write conditions instead
            props := uze getRelevantProperties(params)

            for (additional in props additionals) {
                cPath := File new(File new(originalOutPath, uze identifier), additional relative) path
                oPath := "%s.o" format(cPath[0..-3])
                tw write(oPath). write(" ")
            }
        }
        tw nl()
    }

    writeMainTargets: func {
        tw writeln(".PHONY: compile link clean")
        tw nl()

        tw writeln("all:")
        tw writeln("\t$(MAKE) info")
        tw writeln("\t$(MAKE) compile")
        tw writeln("\t$(MAKE) link")
        tw nl()

        tw writeln("info:")
        tw writeln("\t@echo \"===================================\"")
        tw writeln("\t@echo \"System: $(SYSTEM)\"")
        tw writeln("\t@echo \"Arch: $(ARCH)\"")
        tw writeln("\t@echo \"GCC: $(GCC)\"")
        tw writeln("\t@echo \"PKGS: $(PKGS)\"")
        tw writeln("\t@echo \"CFLAGS: $(CFLAGS)\"")
        tw writeln("\t@echo \"LDFLAGS: $(LDFLAGS)\"")
        tw writeln("\t@echo \"THREAD_FLAGS: $(THREAD_FLAGS)\"")
        tw writeln("\t@echo \"EXECUTABLE: $(EXECUTABLE)\"")
        tw writeln("\t@echo \"===================================\"")
        tw nl()

        tw writeln("compile: $(OBJECT_FILES)")
        tw writeln("\t@echo \"Finished compiling for target $(TARGET)\"")
        tw nl()

        tw writeln("link: $(OBJECT_FILES)")
        if(module dummy && params staticLib){
            tw writeln("\t$(AR) rcs -o $(EXECUTABLE) $(OBJECT_FILES)")
        }else{
            tw writeln("\t$(GCC) $(CFLAGS) $(OBJECT_FILES) -o $(EXECUTABLE) $(THREAD_FLAGS) $(LDFLAGS)")
        }

        tw nl()

        tw writeln("clean:")
        tw writeln("\trm -rf $(OBJECT_FILES)")
        tw nl()
    }

    writeObjectTargets: func {
        for(currentModule in toCompile) {
            path := File new(originalOutPath, currentModule getPath("")) getPath()
            oPath := path + ".o"
            cPath := path + ".c"

            tw write(oPath). write(": ").
               write(cPath). write(" ").
               write(path). write(".h ").
               write(path). write("-fwd.h").
               nl()

            tw writeln("\t$(GCC) $(CFLAGS) -c %s -o %s" format(cPath, oPath))
        }

        for (uze in flags uses) {
            // FIXME this is no good for the make driver
            props := uze getRelevantProperties(params)

            for (additional in props additionals) {
                cPath := File new(File new(originalOutPath, uze identifier), additional relative) path
                oPath := "%s.o" format(cPath[0..-3])

                tw write(oPath). write(": ").
                   write(cPath). nl()
                tw write("\t$(GCC) $(CFLAGS) -c %s -o %s\n" format(cPath, oPath))
            }
        } }

    close: func {
        tw close()
    }

}

