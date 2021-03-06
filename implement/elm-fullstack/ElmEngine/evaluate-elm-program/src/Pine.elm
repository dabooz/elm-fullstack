module Pine exposing (..)

import BigInt
import Json.Encode
import Result.Extra


type Expression
    = LiteralExpression Value
    | ListExpression (List Expression)
    | ApplicationExpression { function : Expression, arguments : List Expression }
    | FunctionOrValueExpression String
    | ContextExpansionWithNameExpression ( String, Value ) Expression
    | IfBlockExpression Expression Expression Expression
    | FunctionExpression String Expression


type Value
    = StringOrIntegerValue String
    | ListValue (List Value)
      -- TODO: Replace ExpressionValue with convention for mapping value to expression.
    | ExpressionValue Expression
    | ClosureValue ExpressionContext String Expression


type alias ExpressionContext =
    -- TODO: Test consolidate into simple Value
    { commonModel : List Value
    }


type PathDescription a
    = DescribePathNode a (PathDescription a)
    | DescribePathEnd a


addToContext : List Value -> ExpressionContext -> ExpressionContext
addToContext names context =
    { context | commonModel = names ++ context.commonModel }


evaluateExpression : ExpressionContext -> Expression -> Result (PathDescription String) Value
evaluateExpression context expression =
    case expression of
        LiteralExpression value ->
            Ok value

        ListExpression listElements ->
            listElements
                |> List.map (evaluateExpression context)
                |> Result.Extra.combine
                |> Result.map ListValue
                |> Result.mapError (DescribePathNode "Failed to evaluate list element")

        ApplicationExpression application ->
            evaluateFunctionApplication context application
                |> Result.mapError (DescribePathNode ("Failed application of '" ++ describeExpression application.function ++ "'"))

        FunctionOrValueExpression name ->
            case name of
                "True" ->
                    Ok trueValue

                "False" ->
                    Ok falseValue

                _ ->
                    let
                        beforeCheckForExpression =
                            lookUpNameInContext name context
                                |> Result.mapError (DescribePathNode ("Failed to look up name '" ++ name ++ "'"))
                    in
                    case beforeCheckForExpression of
                        Ok ( ExpressionValue expressionFromLookup, contextFromLookup ) ->
                            evaluateExpression (addToContext contextFromLookup context) expressionFromLookup
                                |> Result.mapError (DescribePathNode "Failed to evaluate expression from name")

                        _ ->
                            Result.map Tuple.first beforeCheckForExpression

        IfBlockExpression condition expressionIfTrue expressionIfFalse ->
            case evaluateExpression context condition of
                Err error ->
                    Err (DescribePathNode "Failed to evaluate condition" error)

                Ok conditionValue ->
                    evaluateExpression context
                        (if conditionValue == trueValue then
                            expressionIfTrue

                         else
                            expressionIfFalse
                        )

        ContextExpansionWithNameExpression expansion expressionInExpandedContext ->
            evaluateExpression
                { context | commonModel = valueFromContextExpansionWithName expansion :: context.commonModel }
                expressionInExpandedContext

        FunctionExpression argumentName expressionInExpandedContext ->
            Ok (ClosureValue context argumentName expressionInExpandedContext)


valueFromContextExpansionWithName : ( String, Value ) -> Value
valueFromContextExpansionWithName ( declName, declValue ) =
    ListValue [ StringOrIntegerValue declName, declValue ]


namedValueFromValue : Value -> Maybe ( String, Value )
namedValueFromValue value =
    case value of
        ListValue [ StringOrIntegerValue elementLabel, elementValue ] ->
            Just ( elementLabel, elementValue )

        _ ->
            Nothing


lookUpNameInContext : String -> ExpressionContext -> Result (PathDescription String) ( Value, List Value )
lookUpNameInContext name context =
    case name |> String.split "." of
        [] ->
            Err (DescribePathEnd "nameElements is empty")

        nameFirstElement :: nameRemainingElements ->
            let
                availableNames =
                    context.commonModel |> List.filterMap namedValueFromValue

                maybeMatchingValue =
                    availableNames
                        |> List.filter (Tuple.first >> (==) nameFirstElement)
                        |> List.head
                        |> Maybe.map Tuple.second
            in
            case maybeMatchingValue of
                Nothing ->
                    Err
                        (DescribePathEnd
                            ("Did not find '"
                                ++ nameFirstElement
                                ++ "'. "
                                ++ (availableNames |> List.length |> String.fromInt)
                                ++ " names available: "
                                ++ (availableNames |> List.map Tuple.first |> String.join ", ")
                            )
                        )

                Just firstNameValue ->
                    if nameRemainingElements == [] then
                        Ok ( firstNameValue, context.commonModel )

                    else
                        case firstNameValue of
                            ListValue firstNameList ->
                                lookUpNameInContext (String.join "." nameRemainingElements)
                                    { commonModel = firstNameList }

                            _ ->
                                Err (DescribePathEnd ("'" ++ nameFirstElement ++ "' has unexpected type: Not a list."))


evaluateFunctionApplication : ExpressionContext -> { function : Expression, arguments : List Expression } -> Result (PathDescription String) Value
evaluateFunctionApplication context application =
    application.arguments
        |> List.map
            (\argumentExpression ->
                evaluateExpression context argumentExpression
                    |> Result.mapError (DescribePathNode ("Failed to evaluate argument '" ++ describeExpression argumentExpression ++ "'"))
            )
        |> Result.Extra.combine
        |> Result.andThen
            (\arguments ->
                evaluateFunctionApplicationWithEvaluatedArgs context { function = application.function, arguments = arguments }
            )


evaluateFunctionApplicationWithEvaluatedArgs : ExpressionContext -> { function : Expression, arguments : List Value } -> Result (PathDescription String) Value
evaluateFunctionApplicationWithEvaluatedArgs context application =
    let
        functionOnTwoBigIntWithBooleanResult functionOnBigInt =
            evaluateFunctionApplicationExpectingExactlyTwoArguments
                { mapArg0 = parseAsBigInt >> Result.mapError DescribePathEnd
                , mapArg1 = parseAsBigInt >> Result.mapError DescribePathEnd
                , apply =
                    \leftInt rightInt ->
                        Ok
                            (if functionOnBigInt leftInt rightInt then
                                trueValue

                             else
                                falseValue
                            )
                }
                application.arguments

        functionOnTwoBigIntWithBigIntResult functionOnBigInt =
            evaluateFunctionApplicationExpectingExactlyTwoArguments
                { mapArg0 = parseAsBigInt >> Result.mapError DescribePathEnd
                , mapArg1 = parseAsBigInt >> Result.mapError DescribePathEnd
                , apply =
                    \leftInt rightInt ->
                        Ok (StringOrIntegerValue (functionOnBigInt leftInt rightInt |> BigInt.toString))
                }
                application.arguments

        functionExpectingOneArgumentOfTypeList functionOnList =
            evaluateFunctionApplicationExpectingExactlyOneArgument
                { mapArg = Ok
                , apply =
                    \argument ->
                        case argument of
                            ListValue list ->
                                list |> functionOnList |> Ok

                            _ ->
                                Err (DescribePathEnd ("Argument is not a list ('" ++ describeValue argument ++ ")"))
                }
                application.arguments

        functionEquals =
            evaluateFunctionApplicationExpectingExactlyTwoArguments
                { mapArg0 = Ok
                , mapArg1 = Ok
                , apply =
                    \leftValue rightValue ->
                        Ok
                            (if leftValue == rightValue then
                                trueValue

                             else
                                falseValue
                            )
                }
                application.arguments

        resultIgnoringAtomBindings =
            evaluateFunctionApplicationIgnoringAtomBindings
                context
                application
    in
    case application.function of
        FunctionOrValueExpression functionName ->
            case functionName of
                "PineKernel.equals" ->
                    functionEquals

                "PineKernel.negate" ->
                    evaluateFunctionApplicationExpectingExactlyOneArgument
                        { mapArg = parseAsBigInt >> Result.mapError DescribePathEnd
                        , apply = BigInt.negate >> BigInt.toString >> StringOrIntegerValue >> Ok
                        }
                        application.arguments

                "PineKernel.listHead" ->
                    functionExpectingOneArgumentOfTypeList (List.head >> Maybe.withDefault (ListValue []))

                "PineKernel.listTail" ->
                    functionExpectingOneArgumentOfTypeList (List.tail >> Maybe.withDefault [] >> ListValue)

                "PineKernel.listCons" ->
                    evaluateFunctionApplicationExpectingExactlyTwoArguments
                        { mapArg0 = Ok
                        , mapArg1 = Ok
                        , apply =
                            \leftValue rightValue ->
                                case rightValue of
                                    ListValue rightList ->
                                        Ok (ListValue (leftValue :: rightList))

                                    _ ->
                                        Err (DescribePathEnd "Right operand for listCons is not a list.")
                        }
                        application.arguments

                "String.fromInt" ->
                    case application.arguments of
                        [ argument ] ->
                            Ok argument

                        _ ->
                            Err
                                (DescribePathEnd
                                    ("Unexpected number of arguments for String.fromInt: "
                                        ++ String.fromInt (List.length application.arguments)
                                    )
                                )

                "(==)" ->
                    functionEquals

                "(++)" ->
                    evaluateFunctionApplicationExpectingExactlyTwoArguments
                        { mapArg0 = Ok
                        , mapArg1 = Ok
                        , apply =
                            \leftValue rightValue ->
                                case ( leftValue, rightValue ) of
                                    ( StringOrIntegerValue leftLiteral, StringOrIntegerValue rightLiteral ) ->
                                        Ok (StringOrIntegerValue (leftLiteral ++ rightLiteral))

                                    ( ListValue leftList, ListValue rightList ) ->
                                        Ok (ListValue (leftList ++ rightList))

                                    _ ->
                                        Err (DescribePathEnd "Unexpected combination of operands.")
                        }
                        application.arguments

                "(+)" ->
                    functionOnTwoBigIntWithBigIntResult BigInt.add

                "(-)" ->
                    functionOnTwoBigIntWithBigIntResult BigInt.sub

                "(*)" ->
                    functionOnTwoBigIntWithBigIntResult BigInt.mul

                "(//)" ->
                    functionOnTwoBigIntWithBigIntResult BigInt.div

                "(<)" ->
                    functionOnTwoBigIntWithBooleanResult BigInt.lt

                "(<=)" ->
                    functionOnTwoBigIntWithBooleanResult BigInt.lte

                "(>)" ->
                    functionOnTwoBigIntWithBooleanResult BigInt.gt

                "(>=)" ->
                    functionOnTwoBigIntWithBooleanResult BigInt.gte

                "not" ->
                    evaluateFunctionApplicationExpectingExactlyOneArgument
                        { mapArg = Ok
                        , apply =
                            \argument ->
                                if argument == trueValue then
                                    Ok falseValue

                                else
                                    Ok trueValue
                        }
                        application.arguments

                _ ->
                    resultIgnoringAtomBindings

        _ ->
            resultIgnoringAtomBindings


evaluateFunctionApplicationIgnoringAtomBindings : ExpressionContext -> { function : Expression, arguments : List Value } -> Result (PathDescription String) Value
evaluateFunctionApplicationIgnoringAtomBindings context application =
    evaluateExpression context application.function
        |> Result.mapError (DescribePathNode ("Failed to evaluate function expression '" ++ describeExpression application.function ++ "'"))
        |> Result.andThen
            (\functionOrValue ->
                case application.arguments of
                    [] ->
                        Ok functionOrValue

                    firstArgument :: remainingArguments ->
                        let
                            continueWithClosure closureContext argumentName functionExpression =
                                evaluateFunctionApplicationIgnoringAtomBindings
                                    (addToContext
                                        [ valueFromContextExpansionWithName ( argumentName, firstArgument ) ]
                                        closureContext
                                    )
                                    { function = functionExpression, arguments = remainingArguments }
                                    |> Result.mapError
                                        (DescribePathNode
                                            ("Failed application of '"
                                                ++ describeExpression application.function
                                                ++ "' with argument '"
                                                ++ argumentName
                                            )
                                        )
                        in
                        case functionOrValue of
                            ExpressionValue (FunctionExpression argumentName functionExpression) ->
                                continueWithClosure context argumentName functionExpression

                            ClosureValue closureContext argumentName functionExpression ->
                                continueWithClosure closureContext argumentName functionExpression

                            _ ->
                                Err
                                    (DescribePathEnd
                                        ("Failed to apply: Value "
                                            ++ describeValue functionOrValue
                                            ++ " is not a function (Too many arguments)."
                                        )
                                    )
            )


parseAsBigInt : Value -> Result String BigInt.BigInt
parseAsBigInt value =
    case value of
        StringOrIntegerValue stringOrInt ->
            BigInt.fromIntString stringOrInt
                |> Result.fromMaybe ("Failed to parse as integer: " ++ stringOrInt)

        ListValue _ ->
            Err "Unexpected type of value: List"

        ExpressionValue _ ->
            Err "Unexpected type of value: ExpressionValue"

        ClosureValue _ _ _ ->
            Err "Unexpected type of value: ClosureValue"


intFromBigInt : BigInt.BigInt -> Result String Int
intFromBigInt bigInt =
    case bigInt |> BigInt.toString |> String.toInt of
        Nothing ->
            Err "Failed to String.toInt"

        Just int ->
            if String.fromInt int /= BigInt.toString bigInt then
                Err "Integer out of supported range for String.toInt"

            else
                Ok int


evaluateFunctionApplicationExpectingExactlyTwoArguments :
    { mapArg0 : Value -> Result (PathDescription String) arg0
    , mapArg1 : Value -> Result (PathDescription String) arg1
    , apply : arg0 -> arg1 -> Result (PathDescription String) Value
    }
    -> List Value
    -> Result (PathDescription String) Value
evaluateFunctionApplicationExpectingExactlyTwoArguments configuration arguments =
    case arguments of
        [ arg0, arg1 ] ->
            case configuration.mapArg0 arg0 of
                Err error ->
                    Err (DescribePathNode "Failed to map argument 0" error)

                Ok mappedArg0 ->
                    case configuration.mapArg1 arg1 of
                        Err error ->
                            Err (DescribePathNode "Failed to map argument 1" error)

                        Ok mappedArg1 ->
                            configuration.apply mappedArg0 mappedArg1

        _ ->
            Err
                (DescribePathEnd
                    ("Unexpected number of arguments for: "
                        ++ String.fromInt (List.length arguments)
                    )
                )


evaluateFunctionApplicationExpectingExactlyOneArgument :
    { mapArg : Value -> Result (PathDescription String) arg
    , apply : arg -> Result (PathDescription String) Value
    }
    -> List Value
    -> Result (PathDescription String) Value
evaluateFunctionApplicationExpectingExactlyOneArgument configuration arguments =
    case arguments of
        [ arg ] ->
            case configuration.mapArg arg of
                Err error ->
                    Err (DescribePathNode "Failed to map argument" error)

                Ok mappedArg ->
                    configuration.apply mappedArg

        _ ->
            Err
                (DescribePathEnd
                    ("Unexpected number of arguments for: "
                        ++ String.fromInt (List.length arguments)
                    )
                )


trueValue : Value
trueValue =
    tagValue "True" []


falseValue : Value
falseValue =
    tagValue "False" []


tagValue : String -> List Value -> Value
tagValue tagName tagArguments =
    ListValue [ StringOrIntegerValue tagName, ListValue tagArguments ]


tagValueExpression : String -> List Expression -> Expression
tagValueExpression tagName tagArgumentsExpressions =
    ListExpression [ LiteralExpression (StringOrIntegerValue tagName), ListExpression tagArgumentsExpressions ]


describeExpression : Expression -> String
describeExpression expression =
    case expression of
        FunctionOrValueExpression name ->
            "name(" ++ name ++ ")"

        ListExpression list ->
            "[" ++ String.join "," (list |> List.map describeExpression) ++ ")"

        LiteralExpression literal ->
            "literal(" ++ describeValue literal ++ ")"

        ApplicationExpression application ->
            "application(" ++ describeExpression application.function ++ ")"

        FunctionExpression argumentName functionExpression ->
            "function(" ++ argumentName ++ ", " ++ describeExpression functionExpression ++ ")"

        IfBlockExpression _ _ _ ->
            "if-block"

        ContextExpansionWithNameExpression ( newName, _ ) _ ->
            "context-expansion(" ++ newName ++ ")"


describeValue : Value -> String
describeValue value =
    case value of
        StringOrIntegerValue string ->
            "StringOrIntegerValue " ++ Json.Encode.encode 0 (Json.Encode.string string)

        ListValue list ->
            "[" ++ String.join ", " (List.map describeValue list) ++ "]"

        ExpressionValue expression ->
            "expression(" ++ describeExpression expression ++ ")"

        ClosureValue _ argumentName expression ->
            "closure(" ++ argumentName ++ "," ++ describeExpression expression ++ ")"
