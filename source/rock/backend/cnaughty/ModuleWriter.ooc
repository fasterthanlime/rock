import structs/List
import ../../middle/[Module, Include, Import, TypeDecl, FunctionDecl,
       CoverDecl, ClassDecl, OperatorDecl, InterfaceDecl, VariableDecl,
       Type, FuncType, Argument, StructLiteral]
import ../../frontend/BuildParams
import CoverDeclWriter, ClassDeclWriter, VersionWriter, Skeleton

ModuleWriter: abstract class extends Skeleton {

    write: static func (this: Skeleton, module: Module) {

        hName    := "___"+ module getUnderName() + "___"
        hFwdName := "___"+ module getUnderName() + "_fwd___"

        /* write the fwd-.h file */
        current = fw
        current       app("#ifndef "). app(hFwdName)
        current nl(). app("#define "). app(hFwdName). nl()

        // write all includes
        for(inc: Include in module includes) {
            visitInclude(this, inc)
        }
        if(!module includes empty?()) current nl()

        for(uze in module uses) {
            for(inc in uze useDef includes) {
                visitInclude(this, inc)
            }
        }

        // write all type forward declarations
        writeTypesForward(this, module, false) // non-metas first
        writeTypesForward(this, module, true)  // then metas
        if(!module types empty?()) current nl()

        // write imports' includes
        imports := classifyImports(this, module)
        for(imp in imports) {
            inc := imp getModule() getPath("-fwd.h")
            current nl(). app("#include <"). app(inc). app(">")
        }

        // write all func types typedefs
        for(funcType in module funcTypesMap) {
            writeFuncType(this, funcType, null)
        }

        /* write the .h file */
        current = hw
        current       app("#ifndef "). app(hName)
        current nl(). app("#define "). app(hName). nl()

        current nl(). app("#include <"). app(module getPath("-fwd.h")). app(">")

		// include .h-level imports (which contains types we extend)
        for(imp in imports) {
            if(!imp isTight) continue
            inc := imp getModule() getPath(".h")
            current nl(). app("#include <"). app(inc). app(">")
        }
        current nl()

        /* write the .c file */
        current = cw

        // write include to the module's. h file
        current app("#include <"). app(module getPath(".h")). app(">")

        // now loose imports, in the .c it's safe =)
        for(imp in imports) {
            if(imp isTight) continue
            inc := imp getModule() getPath(".h")
            current nl(). app("#include <"). app(inc). app(">")
        }
        current nl()
        
        // write the .c part of all global variables
        for(stmt in module body) {
            if(stmt instanceOf?(VariableDecl) && !stmt as VariableDecl getType() instanceOf?(AnonymousStructType)) {
                vd := stmt as VariableDecl
                // TODO: add 'local'
                if(vd isExtern() && !vd isProto()) continue
                
                current = cw
                current nl()
                if(vd isStatic()) current app("static ")
                vd getType() write(current, vd getFullName())
                current app(';')
            }
        }

        // write all types, non-metas first, then metas
        for(tDecl: TypeDecl in module types) {
            if(tDecl isMeta) continue
            tDecl accept(this)
        }
        for(tDecl: TypeDecl in module types) {
            if(!tDecl isMeta) continue
            tDecl accept(this)
        }
        
        // write the .h part of all global variables
        for(stmt in module body) {
            if(stmt instanceOf?(VariableDecl) && !stmt as VariableDecl getType() instanceOf?(AnonymousStructType)) {
                vd := stmt as VariableDecl
                // TODO: add 'local'
                if(vd isExtern() && !vd isProto()) continue
                
                if(!vd isStatic()) {
                    current = fw
                    current nl(). app("extern ")
                    vd getType() write(current, vd getFullName())
                    current app(';')
                }
            }
        }

        // write load function
        current = fw
        current nl(). app("void "). app(module getLoadFuncName()). app("();")
        current = cw
        current nl(). app("void "). app(module getLoadFuncName()). app("() {"). tab()

        toInit := module getImportsToInit()

        if (!toInit empty?() || !module types empty?() || !module body empty?()) {

            current nl(). app("static "). app("int __done__ = 0;"). nl(). app("if (!__done__++)"). app("{"). tab()

            for (imp in toInit) {
                current nl(). app(imp getModule() getLoadFuncName()). app("();")
            }

            for (type in module types) {
                if(type instanceOf?(ClassDecl)) {
                    cDecl := type as ClassDecl
                    finalScore: Int
                    loadFunc := cDecl getFunction(ClassDecl LOAD_FUNC_NAME, null, null, finalScore&)
                    if(loadFunc) {
                        if(cDecl getVersion()) VersionWriter writeStart(this, cDecl getVersion())
                        current nl(). app(loadFunc getFullName()). app("();")
                        if(cDecl getVersion()) VersionWriter writeEnd(this)
                    }
                }
            }

            for(stmt in module body) {
                if(stmt instanceOf?(VariableDecl) && !stmt as VariableDecl getType() instanceOf?(AnonymousStructType)) {
                    vd := stmt as VariableDecl
                    if(vd isExtern() || vd getExpr() == null) continue
                    current nl(). app(vd getFullName()). app(" = "). app(vd getExpr()). app(';')
                } else {
                    writeLine(stmt)
                }
            }
            current untab(). nl(). app("}")
        }

        current untab(). nl(). app("}"). nl()

        // write all addons
        for(addon in module addons) {
            addon accept(this)
        }

        // write all functions
        for(fDecl in module functions) {
            fDecl accept(this)
        }

        // write all operator overloads
        for(oDecl in module operators) {
            oDecl accept(this)
        }

        // header end
        current = hw
        current nl(). nl(). app("#endif")

        // forward-header end
        current = fw
        current nl(). nl(). app("#endif")

        // Write a default main if none provided in source
        if(module main && !module functions contains?("main")) {
            writeDefaultMain(this)
        }

    }

    writeFunctionAlias: static func (this: Skeleton, fDecl: FunctionDecl, tDecl: TypeDecl) {
        fullName := fDecl getFullName()
        if(fDecl getName() != fullName) {
            hw nl(). app("#define ")
            if(tDecl) {
                hw app(tDecl getNonMeta() getName()) .app('_')
            }
            hw app(fDecl getName())
            if(fDecl getSuffix()) hw app('_'). app(fDecl getSuffix())

            // write macro definition args
            hw app("(")
            isFirst := true

            /* Step 1 : write this, if any */
            if(fDecl isMember() && !fDecl isStatic()) {
                if(isFirst) isFirst = false
                else        hw app(", ")
                hw app("_this_")
            }

            /* Step 2: write the return arguments, if any */
            for(retArg in fDecl getReturnArgs()) {
                if(isFirst) isFirst = false
                else        hw app(", ")
                hw app(retArg getName())
            }
            
            // We eliminate any generic variable that is passed as a "true" function argument
            // E.g. in __va_call: func <T> (f: Func <T> (T), T: Class, arg: T)
            // T is passed as a first param while it shouldnt as it is passed later :D
            typeArgs := fDecl typeArgs filter(|arg| fDecl args each(|rarg| if(arg getName() == rarg getName()) return true); false)
            /* Step 3 : write generic type args */
            for(typeArg in typeArgs) {
                if(isFirst) isFirst = false
                else hw app(", ")
                hw app(typeArg getName())
            }


            /* Step 4 : write real args */
            for(arg in fDecl args) {
                if(isFirst) isFirst = false
                else hw app(", ")
                if(arg instanceOf?(VarArg)) hw app("...")
                else hw app(arg getName())
            }

            hw app(") ")

            // cast the return type if necessary (to avoid C warnings)
            if(fDecl getReturnType() isPointer() || fDecl getReturnType() getRef() instanceOf?(ClassDecl)) {
                hw app("(void*) ")
            }
            hw app(fullName). app("(")

            /* Step 1 : write this, if any */
            isFirst = true
            if(fDecl isMember() && !fDecl isStatic()) {
                if(isFirst) isFirst = false
                else        hw app(", ")
                hw app("(void*) (_this_)")
            }

            /* Step 2: write the return arguments, if any */
            for(retArg in fDecl getReturnArgs()) {
                if(isFirst) isFirst = false
                else        hw app(", ")
                hw app('('). app(retArg getName()). app(')')
            }

            /* Step 3 : write generic type args */
            for(typeArg in typeArgs) {
                if(isFirst) isFirst = false
                else        hw app(", ")
                hw app('('). app(typeArg getName()). app(')')
            }

            // write function call args, casted if necessary (to avoid C warnings)
            for(arg in fDecl args) {
                if(isFirst) isFirst = false
                else        hw app(", ")
                if(arg instanceOf?(VarArg)) {
                    hw app("__VA_ARGS__")
                } else {
                    if(arg getType() isPointer() || arg getType() getRef() instanceOf?(ClassDecl)) {
                        hw app("(void*) ")
                    }
                    hw app("("). app(arg getName()). app(")")
                }
            }
            hw app(")")
        }
    }

    /** Write default main function */
    writeDefaultMain: static func (this: Skeleton) {
        // If just outputing .o files, do not add a default main
        if(!params defaultMain) return

        cw nl(). nl(). app("int main() "). openBlock()
        cw nl(). app("GC_INIT();")
        cw nl(). app(module getLoadFuncName()). app("();")
        cw nl(). app("return 0;")
        cw closeBlock(). nl()
    }

    writeFuncType: static func (this: Skeleton, funcType: FuncType, customName: String) {
        name: String = customName ? customName : funcType toMangledString()
        current nl(). nl().  app("#ifndef "). app(name). app("__DEFINE")
        current nl(). app("#define "). app(name). app("__DEFINE"). nl()
	current nl(). app("typedef ")
        writeFuncPointer(this, funcType, name)
        current app(';')
        current nl(). nl().  app("#endif"). nl()
    }

    writeFuncPointer: static func (this: Skeleton, funcType: FuncType, name: String) {
        if(funcType returnType == null || funcType returnType isGeneric()) {
	    current app("void")
        } else {
            current app(funcType returnType)
        }
        current app(" (*"). app(name). app(")(")

        isFirst := true
        /* Step 1: no this here */

        /* Step 2 : write generic return arg, if any */
        if(funcType returnType != null && funcType returnType isGeneric()) {
            if(isFirst) isFirst = false
            else        current app(", ")
            current app(funcType returnType)
        }

        /* Step 3 : write generic type args */
        if(funcType typeArgs) for(typeArg in funcType typeArgs) {
            if(isFirst) isFirst = false
            else        current app(", ")
            current app(typeArg getType())
        }

        /* Step 4 : write real args */
        for(argType in funcType argTypes) {
	    if(isFirst) isFirst = false
            else        current app(", ")
	    current app(argType)
        }

	/* Step 5: write context, if any */
	if(funcType isClosure) {
	    if(isFirst) isFirst = false
            else        current app(", ")
	    // we don't know the type of the closure-context, so void* will do just fine. Thanks, C!
	    current app("void*")
	}

        current app(')')
    }

    /** Classify imports between 'tight' and 'loose' */
    classifyImports: static func (this: Skeleton, module: Module) -> List<Import> {

        imports := module getAllImports() clone()

        for(selfDecl in module getTypes()) {
            for(imp in imports) {
                if(selfDecl getSuperRef() != null && selfDecl getSuperRef() getModule() == imp getModule()) {
                    // tighten imports of modules which contain classes we extend
                    imp isTight = true
                } else if(imp getModule() types getKeys() contains?("Class")) {
                    // tighten imports of core module
                    imp isTight = true
                } else {
                    for(member in selfDecl getVariables()) {
                        ref := member getType() getRef()
                        if(!ref instanceOf?(CoverDecl)) continue
                        coverDecl := ref as CoverDecl
                        if(coverDecl getFromType() != null) continue
                        if(coverDecl getModule() != imp getModule()) continue
                        // uses compound cover, tightening!
                        imp isTight = true
                        continue
                    }
                    for(interfaceType in selfDecl interfaceTypes) {
                        if(interfaceType getRef() as TypeDecl getModule() == imp getModule()) {
                            imp isTight = true
                            break
                        }
                    }
                }
            }
        }

        imports

    }

    writeTypesForward: static func (this: Skeleton, module: Module, meta: Bool) {

        for(tDecl: TypeDecl in module types) {
            if(tDecl getInterfaceTypes() getSize() > 0) {
                for(interfaceDecl in tDecl getInterfaceDecls()) {
                    if(!meta) {
                        ClassDeclWriter writeStructTypedef(this, interfaceDecl)
                        ClassDeclWriter writeStructTypedef(this, interfaceDecl getMeta())
                    }
                }
            }

            if(tDecl isMeta != meta) continue

            match {
                case tDecl instanceOf?(ClassDecl) =>
                    ClassDeclWriter writeStructTypedef(this, tDecl as ClassDecl)
                    if(tDecl instanceOf?(InterfaceDecl)) {
                        CoverDeclWriter writeTypedef(this, tDecl as InterfaceDecl getFatType())
                    }
                case tDecl instanceOf?(CoverDecl) =>
                    CoverDeclWriter writeTypedef(this, tDecl as CoverDecl)
            }
        }

    }

    /** Write an include */
    visitInclude: static func (this: Skeleton, inc: Include) {

        if(inc verzion) VersionWriter writeStart(this, inc verzion)

        for(define in inc defines) {
            current nl(). app("#ifndef "). app(define name)
            current nl(). app("#define "). app(define name)
            if(define value != null) {
                current app(' '). app(define value)
            }
            current nl(). app("#define "). app(define name). app("___defined")
            current nl(). app("#endif")
        }

        current nl(). app("#include ")
        template := (inc mode == IncludeMode BRACKETED) ? "<%s>" : "\"%s\""
        current app(template format(inc path))

        for(define in inc defines) {
            current nl(). app("#ifdef "). app(define name). app("___defined")
            current nl(). app("#undef "). app(define name)
            current nl(). app("#undef "). app(define name). app("___defined")
            current nl(). app("#endif")
        }

        if(inc verzion) VersionWriter writeEnd(this)

    }

}
