import io/File, text/EscapeSequence
import structs/[HashMap, ArrayList, List, OrderedMultiMap]
import ../frontend/[Token, BuildParams, PathList, AstBuilder]
import ../utils/FileUtils
import Node, FunctionDecl, Visitor, Import, Include, Use, UseDef, TypeDecl,
       FunctionCall, Type, Declaration, VariableAccess, OperatorDecl,
       Scope, NamespaceDecl, BaseType, FuncType, Addon
import tinker/[Response, Resolver, Trail, Errors]

Module: class extends Node {

    // statistics house-keeping
    timesImported := 0
    timesLooped := 0
    
    // true if this module is a dummy only used to get imports!
    dummy := false

    // if this module is out-of-date, 'dead' is set to true.
    dead: Bool { get set }

    // all variants of useful paths
    path, fullName, simpleName, underName, pathElement, oocPath: String
    
    // mostly controls the generation of an implicit main
    main := false

    // 
    types      := OrderedMultiMap<String, TypeDecl> new()
    addons     := ArrayList<Addon> new()
    functions  := OrderedMultiMap<String, FunctionDecl> new()
    operators  := ArrayList<OperatorDecl> new()

    includes   := ArrayList<Include> new()
    imports    := ArrayList<Import> new()
    namespaces := HashMap<String, NamespaceDecl> new()
    uses       := ArrayList<Use> new()

    funcTypesMap := HashMap<String, FuncType> new()

    body       := Scope new()

    lastModified : Long

    params: BuildParams { get set }

    init: func ~module (.fullName, =pathElement, =params, .token) {
        super(token)
        this path = (File separator == '/') ? fullName : fullName replaceAll('/', File separator)
        this oocPath = pathElement + File separator + path + ".ooc"

        // win32 fix - sometimes we get fullName(s) with '\' in the input
        this fullName = fullName replaceAll(File separator, '/')
        idx := this fullName lastIndexOf('/')

        match idx {
            case -1 =>
                simpleName = this fullName clone()
            case =>
                simpleName = this fullName substring(idx + 1)
        }

        underName = sanitize(this fullName)
        
        dead = false
    }

    clone: func -> This {
        raise(This, "Can't clone Module")
        null
    }

    getLoadFuncName: func -> String { getUnderName() + "_load" }
    getFullName:     func -> String { fullName }
    getUnderName:    func -> String { underName }
    getPathElement:  func -> String { pathElement }
    getSourceFolderName: func -> String {
        "ooc/%s" format(getUseDef() identifier)
    }

    getUseDef: func -> UseDef {
        uze := params sourcePathTable get(pathElement)
        if (!uze) {
            message :=  "Module %s has no corresponding use! pathElement = %s" format(fullName, pathElement)
            Exception new(message) throw()
        }
        uze
    }

    getPath: func (suffix := "") -> String {
        base := getSourceFolderName()
        File new(base, path) path + suffix
    }

    getLocalPath: func (suffix := "") -> String {
        File new(File new(pathElement) name, path) path + suffix
    }

    getOocPath: func -> String {
        oocPath
    }

    /**
     * TODO: this is redundant with some stuff in Driver, merge those
     */
    collectDeps: func -> List<Module> {
        _collectDeps(ArrayList<Module> new())
    }

    _collectDeps: func (list: List<Module>) -> List<Module> {
        list add(this)
        for (imp in getAllImports()) {
            if (imp getModule() == null) continue // what can we do about it? nothing.
            if (!list contains?(imp getModule())) {
                imp getModule() _collectDeps(list)
            }
        }
        list
    }

    addFuncType: func (hashName: String, funcType: FuncType) {
        if (!funcTypesMap contains?(hashName)) {
            funcTypesMap put(hashName, funcType)
        }
    }

    sanitize: func(str: String) -> String {
        assert (str != null)
        assert (str _buffer != null)
        result := str _buffer clone()
        for (i in 0..result length()) {
            current := result[i]
            if (!current alphaNumeric?()) {
                result[i] = '_'
            }
        }
        if (result size > 0 && !result[0] alpha?()) result prepend("_")
        result toString()
    }

    addFunction: func (fDecl: FunctionDecl) {
        // don't add empty-named functions
        if (fDecl name empty?()) return

        hash := TypeDecl hashName(fDecl)
        old := functions get(hash)
        if (old != null) {
            if ((old verzion == fDecl verzion) ||
                (old verzion != null && fDecl verzion != null && old verzion equals?(fDecl verzion))) {

                params errorHandler onError(FunctionRedefinition new(old, fDecl))
                return
            }
        }
        functions put(hash, fDecl)
    }

    addAddon: func (addon: Addon) {
        addons add(addon)
    }

    addType: func (tDecl: TypeDecl) {
        old := types get(tDecl name) as TypeDecl
        if (old != null) {
            if ((old verzion == tDecl verzion) ||
                (old verzion != null && tDecl verzion != null && old verzion equals?(tDecl verzion))) {
                params errorHandler onError(TypeRedefinition new(old, tDecl))
                return
            }
        }

        types put(tDecl name, tDecl)
        if (tDecl hasMeta?() && tDecl getMeta()) {
            addType(tDecl getMeta())
        }
    }

    addOperator: func (oDecl: OperatorDecl) {
        operators add(oDecl)
    }

    addImport: func (imp: Import) {
        if (imp getModule() == this) {
            // don't add imports to ourselves (that can happen in the SDK's lang/ modules)
            return
        }
        imports add(imp)
    }

    addInclude: func (inc: Include) {
        includes add(inc)
    }

    addNamespace: func (nDecl: NamespaceDecl) {
        namespaces put(nDecl getName(), nDecl)
    }

    hasNamespace: func (name: String) -> Bool {
        namespaces contains?(name)
    }

    getNamespace: func (name: String) -> NamespaceDecl {
        namespaces get(name)
    }

    addUse: func (uze: Use) {
        uses add(uze)
        if (uze useDef) for (imp in uze useDef imports) {
            // todo: make use imports only findable in the SourcePath specified.
            addImport(Import new(imp, uze token))
        }
    }

    getOperators: func -> List<OperatorDecl> { operators }
    getFunctions: func -> OrderedMultiMap<String, FunctionDecl>  { functions }
    getTypes:     func -> OrderedMultiMap<String, TypeDecl>  { types }
    getUses:      func -> List<Use>          { uses }

    accept: func (visitor: Visitor) { visitor visitModule(this) }

    /** @return global (e.g. non-namespaced) imports */
    getGlobalImports: func -> List<Import> { imports }

    /** @return all imports, including those in namespaces */
    getAllImports: func -> List<Import> {
        if (namespaces empty?()) return imports

        list := ArrayList<Import> new()
        list addAll(getGlobalImports())
        for (namespace in namespaces) {
            list addAll(namespace getImports())
        }
        return list
    }

    eachImport: func (f: Func (Import) -> Bool) {
        for (imp in imports) {
            if (!f(imp)) return
        }
        for (namespace in namespaces) {
            for (imp in namespace getImports()) {
                if (!f(imp)) return
            }
        }
    }

    /**
     * @return true if this module or one of its dependencies imports `other`
     */
    hasLink?: func (other: Module) -> Bool {
        // might be ourselves, you never know..
        if (other == this) return true

        found := false

        // search in direct imports first
        eachImport(|imp|
            if (imp module == other) {
                found = true // all good! we're importing it directly.
                return false // break
            }
            true
        )
        if (found) return true

        // do a thorough search
        done := ArrayList<Module> new()
        todo := ArrayList<Module> new()

        eachImport(|imp|
            todo add(imp module)
            true
        )

        while (!todo empty?()) {
            module := todo removeAt(0)
            done add(module)

            module eachImport(|imp|
                if (!imp isTight) {
                    return true // continue, only considering tight imports
                }

                if (imp module == other) {
                    found = true
                    return false // break
                } else if (!done contains?(imp module)) {
                    // check it out then
                    todo add(imp module)
                }

                true // continue
            )

            if (found) break // else, keep looking
        }

        found
    }

    resolveAccess: func (access: VariableAccess, res: Resolver, trail: Trail) -> Int {

        resolveAccessNonRecursive(access, res, trail)
        if (access ref) return 0

        for (imp in getGlobalImports()) {
            imp getModule() resolveAccessNonRecursive(access, res, trail)
            if (access ref) return 0
        }

        namespace := namespaces get(access getName())
        if (namespace != null) {
            //printf("resolved access %s to namespace %s!\n", access getName(), namespace toString())
            access suggest(namespace)
        }

        0

    }

    resolveAccessNonRecursive: func (access: VariableAccess, res: Resolver, trail: Trail) -> Int {

        if (access debugCondition() || res params veryVerbose) {
            "resolveAccess(%s) in %s" printfln(access toString(), toString())
        }

        ref := null as Declaration

        for (f in functions) {
            if (f name == access name) {
                if (access suggest(f)) return 0
            }
        }

        ref = types get(access name)
        if (ref != null && access suggest(ref)) {
            return 0
        }

        // That's actually the only place we want to resolve variables from the
        // body - precisely because they're global
        body resolveAccess(access, res, trail)

        0

    }

    resolveCall: func (call: FunctionCall, res: Resolver, trail: Trail) -> Int {
        if (call isMember()) {
            return 0 // hmm no member calls for us
        }

        resolveCallNonRecursive(call, res, trail)

        for (imp in getGlobalImports()) {
            imp getModule() resolveCallNonRecursive(call, res, trail)
        }

        0
    }

    resolveCallNonRecursive: func (call: FunctionCall, res: Resolver, trail: Trail) {

        //printf(" >> Looking for function %s in module %s!\n", call name, fullName)
        fDecl : FunctionDecl = null
        fDecl = functions get(TypeDecl hashName(call name, call suffix))
        if (fDecl) {
            call suggest(fDecl, res, trail)
        }

        if (!call suffix) for (fDecl in functions) {
            if (fDecl name == call name && (call suffix == null)) {
                if (call debugCondition()) "Suggesting fDecl %s for call %s" printfln(fDecl toString(), call toString())
                call suggest(fDecl, res, trail)
            }
        }

    }

    resolveType: func (type: BaseType, res: Resolver, trail: Trail) -> Int {

        ref : Declaration = null

        ref = types get(type name)
        if (ref != null && type suggest(ref)) {
            return 0
        }

        for (imp in getGlobalImports()) {
            ref = imp getModule() types get(type name)
            if (ref != null && type suggest(ref)) {
                return 0
            }
        }

        0

    }

    /**
     * Parse the imports of this module.
     *
     * If resolver is non-null, it means there's a new import that
     * we expect to add to the resolvers list.
     */
    parseImports: func (resolver: Resolver) {
        for (imp in getAllImports()) {
            if (imp module) continue // nothing to do

            // import paths may contain ".." or relative paths - get it straight first
            (_path, impFile, impElement) := AstBuilder getRealImportPath(imp, this, params)
            if (!impFile) {
                params errorHandler onError(ModuleNotFound new(imp))
                continue
            }
            absolutePath := impFile getAbsolutePath()

            // the cache is a key-value store where keys are the absolute paths of modules.
            cached := AstBuilder cache get(absolutePath)
            impLastModified := impFile lastModified()

            // look for path errors on case-insensitive filesystems
            version (windows) {
                longPath := impFile getLongPath()
                importAtom := _path trimLeft(".")
                if (!longPath endsWith?(importAtom)) {
                    params errorHandler onError(InternalError new(imp token, "Import path is case-inconsistent with file system (actual file is %s)" \
                        format(longPath) ))
                }
            }

            // if it's not in the cache or outdated, reparse.
            if (!cached || impLastModified > cached lastModified) {
                if (cached && params veryVerbose) {
                    "%s has been changed, recompiling... (%d vs %d), import path = %s" printfln(_path, impFile lastModified(), cached lastModified, impFile path)
                }

                cached = Module new(_path[0..-5], impElement path, params, nullToken)
                // clean the cache
                AstBuilder cache remove(absolutePath)
                AstBuilder cache put(absolutePath, cached)
                imp setModule(cached)

                cached token = Token new(0, 0, cached)
                if (resolver) resolver addModule(cached)
                
                cached lastModified = impLastModified
                AstBuilder new(impFile path, cached, params)
            }
            
            imp setModule(cached)
            cached parseImports(resolver)
        }
    }

    resolve: func (trail: Trail, res: Resolver) -> Response {

        finalResponse := Response OK

        trail push(this)

        for (inc in includes) {
            response := inc resolve(trail, res)
            if (!response ok()) {
                if (res params veryVerbose) "response of include %s = %s" printfln(inc toString(), response toString())
                finalResponse = response
            }
        }

        for (oDecl in operators) {
            if (oDecl isResolved()) continue
            response := oDecl resolve(trail, res)
            if (!response ok()) {
                if (res params veryVerbose) "response of oDecl %s = %s" printfln(oDecl toString(), response toString())
                finalResponse = response
            }
        }

        for (tDecl in types) {
            if (tDecl isResolved()) continue
            response := tDecl resolve(trail, res)
            if (!response ok()) {
                if (res params veryVerbose) "response of tDecl %s = %s" printfln(tDecl toString(), response toString())
                finalResponse = response
            }
        }

        for (addon in addons) {
            response := addon resolve(trail, res)
            if (!response ok()) {
                if (res params veryVerbose) "response of addon %s = %s" printfln(addon toString(), response toString())
                finalResponse = response
            }
        }

        for (fDecl in functions) {
            if (fDecl isResolved()) continue
            response := fDecl resolve(trail, res)
            if (!response ok()) {
                if (res params veryVerbose) "response of fDecl %s = %s" printfln(fDecl toString(), response toString())
                finalResponse = response
            }
        }

        {
            response := body resolve(trail, res)
            if (!response ok()) {
                if (res params veryVerbose) "response of body = %s" printfln(response toString())
                finalResponse = response
            }
        }

        trail pop(this)

        return finalResponse
    }

    toString: func -> String {
        class name + ' ' + fullName
    }

    replace: func (oldie, kiddo: Node) -> Bool { false }

    isScope: func -> Bool { true }

}

ModuleNotFound: class extends Error {
    imp: Import

    init: func (=imp) {
        super(imp token, "Module not found in sourcepath " + imp path)
    }
}
