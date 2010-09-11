import ../frontend/Token
import Literal, Visitor, Type, BaseType

FloatLiteral: class extends Literal {

    value: Float
    type := static BaseType new("Float", nullToken)

    init: func ~floatLiteral (=value, .token) {
        super(token)
    }

    clone: func -> This { new(value, token) }

    accept: func (visitor: Visitor) { visitor visitFloatLiteral(this) }

    getType: func -> Type { type }

    toString: func -> String { value toString() }

}
