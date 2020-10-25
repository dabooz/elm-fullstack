module ElmEvaluationUsingPine exposing (evaluateExpressionText)

import Elm.Syntax.Expression
import Elm.Syntax.Node
import ElmEvaluation
import Json.Encode
import Pine exposing (PineExpression(..), PineValue(..))
import Result.Extra


evaluateExpressionText : String -> Result String Json.Encode.Value
evaluateExpressionText elmExpressionText =
    case parseElmExpressionString elmExpressionText of
        Err error ->
            Err ("Failed to map from Elm to Pine expression: " ++ error)

        Ok pineExpression ->
            case Pine.evaluatePineExpression [] pineExpression of
                Err error ->
                    Err ("Failed to evaluate Pine expression: " ++ error)

                Ok pineValue ->
                    pineValueAsJson pineValue


pineValueAsJson : PineValue -> Result String Json.Encode.Value
pineValueAsJson pineValue =
    case pineValue of
        PineStringOrInteger string ->
            -- TODO: Use type inference to distinguish between string and integer
            Ok (string |> Json.Encode.string)

        PineList list ->
            list
                |> List.map pineValueAsJson
                |> Result.Extra.combine
                |> Result.mapError (\error -> "Failed to combine list: " ++ error)
                |> Result.map (Json.Encode.list identity)

        PineExpressionValue _ ->
            Err "PineExpressionValue"


parseElmExpressionString : String -> Result String PineExpression
parseElmExpressionString elmExpressionText =
    case ElmEvaluation.parseExpressionFromString elmExpressionText of
        Err error ->
            Err ("Failed to parse Elm syntax: " ++ error)

        Ok elmSyntax ->
            case pineExpressionFromElm elmSyntax of
                Err error ->
                    Err ("Failed to map from Elm to Pine: " ++ error)

                Ok ok ->
                    Ok ok


pineExpressionFromElm : Elm.Syntax.Expression.Expression -> Result String PineExpression
pineExpressionFromElm elmExpression =
    case elmExpression of
        Elm.Syntax.Expression.Literal literal ->
            Ok (PineLiteral (PineStringOrInteger literal))

        Elm.Syntax.Expression.Integer integer ->
            Ok (PineLiteral (PineStringOrInteger (String.fromInt integer)))

        Elm.Syntax.Expression.FunctionOrValue moduleName localName ->
            Ok (PineFunctionOrValue (String.join "." (moduleName ++ [ localName ])))

        Elm.Syntax.Expression.Application application ->
            case application |> List.map (Elm.Syntax.Node.value >> pineExpressionFromElm) |> Result.Extra.combine of
                Err error ->
                    Err ("Failed to map application elements: " ++ error)

                Ok applicationElements ->
                    case applicationElements of
                        appliedFunctionSyntax :: arguments ->
                            Ok (PineApplication { function = appliedFunctionSyntax, arguments = arguments })

                        [] ->
                            Err "Invalid shape of application: Zero elements in the application list"

        Elm.Syntax.Expression.OperatorApplication operator _ leftExpr rightExpr ->
            case
                ( pineExpressionFromElm (Elm.Syntax.Node.value leftExpr)
                , pineExpressionFromElm (Elm.Syntax.Node.value rightExpr)
                )
            of
                ( Ok left, Ok right ) ->
                    Ok
                        (PineApplication
                            { function = PineFunctionOrValue ("(" ++ operator ++ ")")
                            , arguments = [ left, right ]
                            }
                        )

                _ ->
                    Err "Failed to map OperatorApplication left or right expression. TODO: Expand error details."

        Elm.Syntax.Expression.IfBlock elmCondition elmExpressionIfTrue elmExpressionIfFalse ->
            case pineExpressionFromElm (Elm.Syntax.Node.value elmCondition) of
                Err error ->
                    Err ("Failed to map Elm condition: " ++ error)

                Ok condition ->
                    case pineExpressionFromElm (Elm.Syntax.Node.value elmExpressionIfTrue) of
                        Err error ->
                            Err ("Failed to map Elm expressionIfTrue: " ++ error)

                        Ok expressionIfTrue ->
                            case pineExpressionFromElm (Elm.Syntax.Node.value elmExpressionIfFalse) of
                                Err error ->
                                    Err ("Failed to map Elm expressionIfFalse: " ++ error)

                                Ok expressionIfFalse ->
                                    Ok (PineIfBlock condition expressionIfTrue expressionIfFalse)

        Elm.Syntax.Expression.LetExpression letBlock ->
            let
                declarationsResults =
                    letBlock.declarations
                        |> List.map
                            (\declaration ->
                                case Elm.Syntax.Node.value declaration of
                                    Elm.Syntax.Expression.LetFunction letFunctionNode ->
                                        case pineExpressionFromElm (Elm.Syntax.Node.value (Elm.Syntax.Node.value letFunctionNode.declaration).expression) of
                                            Err error ->
                                                Err ("Failed to map expression in let function: " ++ error)

                                            Ok letFunctionExpression ->
                                                Ok
                                                    ( Elm.Syntax.Node.value (Elm.Syntax.Node.value letFunctionNode.declaration).name
                                                    , letFunctionExpression
                                                    )

                                    Elm.Syntax.Expression.LetDestructuring _ _ ->
                                        Err "Destructuring in let block not implemented yet."
                            )
            in
            case declarationsResults |> Result.Extra.combine of
                Err error ->
                    Err ("Failed to map declaration in let block: " ++ error)

                Ok declarations ->
                    case pineExpressionFromElm (Elm.Syntax.Node.value letBlock.expression) of
                        Err error ->
                            Err ("Failed to map expression in let block: " ++ error)

                        Ok expressionInExpandedContext ->
                            case declarations of
                                [] ->
                                    Ok expressionInExpandedContext

                                firstDeclaration :: remainingDeclarations ->
                                    let
                                        pineValueFromDeclaration ( declName, declValue ) =
                                            PineList [ PineStringOrInteger declName, PineExpressionValue declValue ]
                                    in
                                    Ok
                                        (remainingDeclarations
                                            |> List.foldl
                                                (\declaration combinedExpr ->
                                                    PineContextExpansion (pineValueFromDeclaration declaration) combinedExpr
                                                )
                                                (PineContextExpansion (pineValueFromDeclaration firstDeclaration) expressionInExpandedContext)
                                        )

        Elm.Syntax.Expression.ParenthesizedExpression parenthesizedExpression ->
            pineExpressionFromElm (Elm.Syntax.Node.value parenthesizedExpression)

        _ ->
            Err
                ("Unsupported type of expression: "
                    ++ (elmExpression |> Elm.Syntax.Expression.encode |> Json.Encode.encode 0)
                )