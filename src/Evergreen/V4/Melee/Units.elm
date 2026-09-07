module Evergreen.V4.Melee.Units exposing (..)


type Side
    = Bottom
    | Top


type alias Sided a =
    { bottom : a
    , top : a
    }


type FrameCount
    = FrameCount Int


type alias WorldPoint =
    { x : Int
    , y : Int
    }


type alias WorldExtent =
    { width : Int
    , height : Int
    }


type Wait
    = Wait Int


type Facing
    = Facing Int


type Angle
    = Angle Int


type alias VelocityDesc =
    { travelAngle : Angle
    , vector : WorldExtent
    , fract : WorldExtent
    , error : WorldExtent
    , incr : WorldExtent
    }
