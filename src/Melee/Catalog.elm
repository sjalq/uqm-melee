module Melee.Catalog exposing (..)

import Melee.Ship exposing (..)


type alias Info =
    { name : String, vessel : String, help : String, sprite : String, icon : String }


all : List ShipKind
all =
    [ Androsynth, Arilou, Chenjesu, Chmmr, Druuge, Earthling, Ilwrath, KohrAh, Melnorme, Mmrnmhrm, Mycon, Orz, Pkunk, Shofixti, Slylandro, Spathi, Supox, Syreen, Thraddash, Umgah, UrQuan, Utwig, Vux, Yehat, ZoqFotPik ]


info : ShipKind -> Info
info kind =
    case kind of
        Androsynth ->
            { name = "Androsynth", vessel = "Guardian", help = "Bubbles / comet form", sprite = "/ships/androsynth/guardian-big-", icon = "/ships/androsynth/guardian-meleeicons-000.png" }

        Arilou ->
            { name = "Arilou", vessel = "Skiff", help = "Auto-aim laser / teleport", sprite = "/ships/arilou/skiff-big-", icon = "/ships/arilou/skiff-meleeicons-000.png" }

        Chenjesu ->
            { name = "Chenjesu", vessel = "Broodhome", help = "Release crystal to shatter / energy-draining DOGI", sprite = "/ships/chenjesu/broodhome-big-", icon = "/ships/chenjesu/broodhome-meleeicons-000.png" }

        Chmmr ->
            { name = "Chmmr", vessel = "Avatar", help = "Laser / tractor beam / defensive satellites", sprite = "/ships/chmmr/avatar-big-", icon = "/ships/chmmr/avatar-meleeicons-000.png" }

        Druuge ->
            { name = "Druuge", vessel = "Mauler", help = "Recoil cannon / sacrifice crew for energy", sprite = "/ships/druuge/mauler-big-", icon = "/ships/druuge/mauler-meleeicons-000.png" }

        Earthling ->
            { name = "Earthling", vessel = "Cruiser", help = "Homing nuclear missile / point defence", sprite = "/ships/human/cruiser-big-", icon = "/ships/human/cruiser-meleeicons-000.png" }

        Ilwrath ->
            { name = "Ilwrath", vessel = "Avenger", help = "Flamethrower / cloak", sprite = "/ships/ilwrath/avenger-big-", icon = "/ships/ilwrath/avenger-meleeicons-000.png" }

        KohrAh ->
            { name = "Kohr-Ah", vessel = "Marauder", help = "Hold spinning blades / fiery ring", sprite = "/ships/kohrah/marauder-big-", icon = "/ships/kohrah/marauder-meleeicons-000.png" }

        Melnorme ->
            { name = "Melnorme", vessel = "Trader", help = "Hold to charge / confusion missile", sprite = "/ships/melnorme/trader-big-", icon = "/ships/melnorme/trader-meleeicons-000.png" }

        Mmrnmhrm ->
            { name = "Mmrnmhrm", vessel = "X-Form", help = "Twin lasers / transform to missile fighter", sprite = "/ships/mmrnmhrm/xform-big-", icon = "/ships/mmrnmhrm/xform-meleeicons-000.png" }

        Mycon ->
            { name = "Mycon", vessel = "Podship", help = "Homing plasma / regenerate crew", sprite = "/ships/mycon/podship-big-", icon = "/ships/mycon/podship-meleeicons-000.png" }

        Orz ->
            { name = "Orz", vessel = "Nemesis", help = "Howitzer / special + turn rotates turret; special + fire launches marines", sprite = "/ships/orz/nemesis-big-", icon = "/ships/orz/nemesis-meleeicons-000.png" }

        Pkunk ->
            { name = "Pkunk", vessel = "Fury", help = "Three-way shot / recharge / chance to resurrect", sprite = "/ships/pkunk/fury-big-", icon = "/ships/pkunk/fury-meleeicons-000.png" }

        Shofixti ->
            { name = "Shofixti", vessel = "Scout", help = "Energy dart / tap special three times to detonate glory device", sprite = "/ships/shofixti/scout-big-", icon = "/ships/shofixti/scout-meleeicons-000.png" }

        Slylandro ->
            { name = "Slylandro", vessel = "Probe", help = "Lightning / harvest asteroids for energy", sprite = "/ships/slylandro/probe-big-", icon = "/ships/slylandro/probe-meleeicons-000.png" }

        Spathi ->
            { name = "Spathi", vessel = "Eluder", help = "Forward gun / rear homing missile", sprite = "/ships/spathi/eluder-big-", icon = "/ships/spathi/eluder-meleeicons-000.png" }

        Supox ->
            { name = "Supox", vessel = "Blade", help = "Rapid pellets / special + turn to strafe; special + thrust to reverse", sprite = "/ships/supox/blade-big-", icon = "/ships/supox/blade-meleeicons-000.png" }

        Syreen ->
            { name = "Syreen", vessel = "Penetrator", help = "Missile / lure and collect enemy crew", sprite = "/ships/syreen/penetrator-big-", icon = "/ships/syreen/penetrator-meleeicons-000.png" }

        Thraddash ->
            { name = "Thraddash", vessel = "Torch", help = "Blaster / afterburner leaves damaging fire", sprite = "/ships/thraddash/torch-big-", icon = "/ships/thraddash/torch-meleeicons-000.png" }

        Umgah ->
            { name = "Umgah", vessel = "Drone", help = "Antimatter cone / reverse zip", sprite = "/ships/umgah/drone-big-", icon = "/ships/umgah/drone-meleeicons-000.png" }

        UrQuan ->
            { name = "UrQuan", vessel = "Dreadnought", help = "Fusion cannon / launch fighters", sprite = "/ships/urquan/dreadnought-big-", icon = "/ships/urquan/dreadnought-meleeicons-000.png" }

        Utwig ->
            { name = "Utwig", vessel = "Jugger", help = "Six-gun salvo / absorb shots into shield energy", sprite = "/ships/utwig/jugger-big-", icon = "/ships/utwig/jugger-meleeicons-000.png" }

        Vux ->
            { name = "Vux", vessel = "Intruder", help = "Laser / limpets slow the enemy", sprite = "/ships/vux/intruder-big-", icon = "/ships/vux/intruder-meleeicons-000.png" }

        Yehat ->
            { name = "Yehat", vessel = "Terminator", help = "Twin cannons / shield", sprite = "/ships/yehat/terminator-big-", icon = "/ships/yehat/terminator-meleeicons-000.png" }

        ZoqFotPik ->
            { name = "ZoqFotPik", vessel = "Stinger", help = "Spray / short-range tongue", sprite = "/ships/zoqfotpik/stinger-big-", icon = "/ships/zoqfotpik/stinger-meleeicons-000.png" }


sprite : ShipKind -> Int -> String
sprite kind facing =
    (info kind).sprite ++ String.padLeft 3 '0' (String.fromInt (modBy 16 facing)) ++ ".png"
