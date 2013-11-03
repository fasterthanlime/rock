import structs/ArrayList
import ../frontend/Token
import Expression, Visitor, Type, Node, FunctionCall, OperatorDecl, BaseType, OverloadStatus
import tinker/[Trail, Resolver, Response, Errors]

UnaryOpType: enum {
    binaryNot        /*  ~  */
    logicalNot       /*  !  */
    unaryMinus       /*  -  */
    unaryPlus        /*  +  */
}

unaryOpRepr := [
	"~",
    "!",
    "-",
    "+"]

UnaryOp: class extends Expression {

    inner: Expression
    type: UnaryOpType
    boolType: BaseType

    resolved? := false
    overloadStatus := OverloadStatus NONE

    init: func ~unaryOp (=inner, =type, .token) {
        super(token)
        boolType = BaseType new("Bool", token)
    }

    clone: func -> This {
        new(inner clone(), type, token)
    }

    accept: func (visitor: Visitor) {
        visitor visitUnaryOp(this)
    }

    isResolved: func -> Bool {
        resolved?
    }

    getType: func -> Type {
        if (type == UnaryOpType logicalNot) return boolType
        inner getType()
    }

    repr: func -> String {
        unaryOpRepr[type as Int - UnaryOpType binaryNot]
    }

    toString: func -> String {
        return repr() + inner toString()
    }

    resolve: func (trail: Trail, res: Resolver) -> Response {

        trail push(this)
        boolType resolve(trail, res)
        {
            response := inner resolve(trail, res)
            if(!response ok()) {
                trail pop(this)
                return response
            }
        }

        trail pop(this)

        {
            response := resolveOverload(trail, res)
            if(!response ok()) return response
        }


        if(overloadStatus == OverloadStatus NONE) {
            if(inner getType()) {
                match type {
                    case UnaryOpType unaryMinus =>
                        if(!inner getType() isNumericType()) {
                            res throwError(InvalidUnaryType new(token,
                                           "Unoverloaded unary minus expects a numeric type, not a %s" format(inner getType() toString())))
                        }
                    case UnaryOpType unaryPlus =>
                        if(!inner getType() isNumericType()) {
                            res throwError(InvalidUnaryType new(token,
                                           "Unoverloaded unary plus expects a numeric type, not a %s" format(inner getType() toString())))
                        }

                        // Replace ourselves with the inner expression.
                        // If we don't, we will get translated to + in C, which is an upcast, not a noop.
                        if(!trail peek() replace(this, inner)) {
                            if(res fatal) {
                                res throwError(CouldntReplace new(token, this, inner, trail))
                            }

                            res wholeAgain(this, "failed to replace ourselves with inner expression, try again")
                        }
                }
            }
        }

        resolved? = true
        return Response OK

    }

    resolveOverload: func (trail: Trail, res: Resolver) -> Response {

        // so here's the plan: we give each operator overload a score
        // depending on how well it fits our requirements (types)

        bestScore := 0
        candidate : OperatorDecl = null

        reqType := trail peek() getRequiredType()

        for(opDecl in trail module() getOperators()) {
            score := getScore(opDecl, reqType)
            if(score == -1) {
                overloadStatus = OverloadStatus WAITING
                res wholeAgain(this, "score of op == -1 !!")
                return Response OK
            }

            if(score > bestScore) {
                bestScore = score
                candidate = opDecl
            }
        }

        for(imp in trail module() getAllImports()) {
            module := imp getModule()
            for(opDecl in module getOperators()) {
                score := getScore(opDecl, reqType)
                if(score == -1) {
                    overloadStatus = OverloadStatus WAITING
                    res wholeAgain(this, "score of %s == -1 !!")
                    return Response OK
                }

                if(score > bestScore) {
                    bestScore = score
                    candidate = opDecl
                }
            }
        }

        if(candidate != null) {
            fDecl := candidate getFunctionDecl()
            fCall := FunctionCall new(fDecl getName(), token)
            fCall getArguments() add(inner)
            fCall setRef(fDecl)
            if(!trail peek() replace(this, fCall)) {
                if(res fatal) res throwError(CouldntReplace new(token, this, fCall, trail))
                overloadStatus = OverloadStatus WAITING
                res wholeAgain(this, "failed to replace oneself, gotta try again =)")
                return Response OK
                //return Response LOOP
            } else {
                overloadStatus = OverloadStatus REPLACED
            }
            res wholeAgain(this, "Just replaced with an operator overloading")
        } else {
            overloadStatus = OverloadStatus NONE
        }

        return Response OK

    }

    getScore: func (op: OperatorDecl, reqType: Type) -> Int {

        symbol := repr()

        if(!(op getSymbol() equals?(symbol))) {
            return 0 // not the right overload type - skip
        }

        fDecl := op getFunctionDecl()

        args := fDecl getArguments()

        //if we have 2 arguments, then it's a binary plus binary
        if(args getSize() == 2) return 0

        if(args getSize() != 1) {
            token module params errorHandler onError(InvalidUnaryOverload new(op token,
                "Ohum, you need 1 argument to override the '%s' operator, not %d" format(symbol, args getSize())))
        }

        if(args get(0) getType() == null || inner getType() == null) { return -1 }

        argScore := args get(0) getType() getScore(inner getType())
        if(argScore == -1) return -1
        reqScore := reqType ? fDecl getReturnType() getScore(reqType) : 0
        if(reqScore == -1) return -1

        return argScore + reqScore

    }

    replace: func (oldie, kiddo: Node) -> Bool {
        match oldie {
            case inner => inner = kiddo; true
            case => false
        }
    }

}

InvalidUnaryOverload: class extends Error {
    init: super func ~tokenMessage
}

InvalidUnaryType: class extends Error {
    init: super func ~tokenMessage
}
