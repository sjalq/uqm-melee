module Mario.Dashboard.Tip exposing
    ( Align(..)
    , Handlers
    , Tip
    , detail
    , isOpen
    , tip
    , view
    , viewBare
    )

{-| Accessible explanation tooltips.

Every metric, chart and control on this dashboard carries one. A native
`title` attribute would be invisible to keyboard users, unusable on
touch, and unstyleable, so this builds a real one instead:

  - mouse: pointer entering the labelled region opens it,
  - keyboard: the trigger is a real `<button>`, so Tab reaches it and
    focus opens the bubble; Escape closes a pinned one,
  - touch: tapping the trigger pins the bubble open and shows a
    dismiss button, because touch has no hover and no blur.

The bubble is tied to its subject with `aria-describedby`, and on narrow
screens the stylesheet docks it to the bottom of the viewport so it is
never clipped by a horizontally scrolling chart.

-}

import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (attribute, class, id, type_)
import Html.Events exposing (onBlur, onClick, onFocus, onMouseEnter, onMouseLeave)


{-| One explanation. `meta` carries the facts the contract insists on
stating for every metric: what the denominator is, what time window it
covers, and whether it came from training or from a fresh audit.
-}
type alias Tip =
    { id : String
    , title : String
    , body : String
    , meta : List ( String, String )
    }


tip : String -> String -> String -> List ( String, String ) -> Tip
tip tipId title body meta =
    { id = tipId, title = title, body = body, meta = meta }


{-| Attach run-specific detail to a tip without moving it.

The page states each fact once, in one short sentence, and keeps the
full reasoning behind the explanation trigger that is already next to
it. A dozen paragraphs printed under a heading pushes the numbers below
the fold and gets skipped; the same paragraphs one keystroke away get
read by the person who actually wants them.

The id, title and meta are preserved, so a detailed tip is still the
same tip: it cannot collide with another bubble or lose its denominator.

-}
detail : Tip -> List String -> Tip
detail base lines =
    if List.isEmpty lines then
        base

    else
        { base | body = String.join " " (base.body :: lines) }


type Align
    = AlignStart
    | AlignEnd


{-| Wiring supplied by the host application. `openId` is the tip that is
currently showing, whether by hover, by focus or by being pinned.
-}
type alias Handlers msg =
    { open : String -> msg
    , close : String -> msg
    , toggle : String -> msg
    , openId : Maybe String
    , pinnedId : Maybe String
    }


isOpen : Handlers msg -> Tip -> Bool
isOpen handlers t =
    handlers.openId == Just t.id


{-| Render `content` followed by its explanation trigger.
-}
view : Handlers msg -> Align -> Tip -> List (Html msg) -> Html msg
view handlers align t content =
    span
        [ class "tip"
        , onMouseEnter (handlers.open t.id)
        , onMouseLeave (handlers.close t.id)
        ]
        (content ++ [ trigger handlers t, bubble handlers align t ])


{-| The trigger on its own, for places that already have their own
layout wrapper and do not want the extra span.
-}
viewBare : Handlers msg -> Align -> Tip -> Html msg
viewBare handlers align t =
    span
        [ class "tip"
        , onMouseEnter (handlers.open t.id)
        , onMouseLeave (handlers.close t.id)
        ]
        [ trigger handlers t, bubble handlers align t ]


trigger : Handlers msg -> Tip -> Html msg
trigger handlers t =
    button
        [ type_ "button"
        , class "tip-trigger"
        , attribute "aria-label" ("Explain: " ++ t.title)
        , attribute "aria-expanded"
            (if isOpen handlers t then
                "true"

             else
                "false"
            )
        , attribute "aria-describedby" (bubbleId t)
        , onFocus (handlers.open t.id)
        , onBlur (handlers.close t.id)
        , onClick (handlers.toggle t.id)
        ]
        [ text "?" ]


bubbleId : Tip -> String
bubbleId t =
    "tip-" ++ t.id


bubble : Handlers msg -> Align -> Tip -> Html msg
bubble handlers align t =
    if isOpen handlers t then
        div
            [ class
                ("tip-bubble"
                    ++ (case align of
                            AlignEnd ->
                                " tip-align-end"

                            AlignStart ->
                                ""
                       )
                )
            , id (bubbleId t)
            , attribute "role" "tooltip"
            ]
            (span [ class "tip-title" ] [ text t.title ]
                :: text t.body
                :: List.map metaLine t.meta
                ++ dismiss handlers t
            )

    else
        text ""


metaLine : ( String, String ) -> Html msg
metaLine ( key, value ) =
    span [ class "tip-meta" ]
        [ Html.b [] [ text (key ++ ": ") ]
        , text value
        ]


dismiss : Handlers msg -> Tip -> List (Html msg)
dismiss handlers t =
    if handlers.pinnedId == Just t.id then
        [ div [ class "tip-dismiss" ]
            [ button
                [ type_ "button"
                , class "btn btn-small"
                , onClick (handlers.toggle t.id)
                ]
                [ text "Dismiss" ]
            ]
        ]

    else
        []
