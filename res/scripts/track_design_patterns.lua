local func = require "track_design_patterns/func"
local coor = require "track_design_patterns/coor"
local arc = require "track_design_patterns/coorarc"
local station = require "track_design_patterns/stationlib"
local pipe = require "track_design_patterns/pipe"
local tdp = {}

local pi = math.pi
local abs = math.abs

tdp.infi = 1e8


tdp.trackList = {"standard.lua", "high_speed.lua"}
tdp.trackWidthList = {5, 5}
tdp.trackType = pipe.exec * function()
    local list = {
        {
            key = "trackType",
            name = _("Track type"),
            values = {_("Standard"), _("High-speed")},
            yearFrom = 1925,
            yearTo = 0
        },
        {
            key = "catenary",
            name = _("Catenary"),
            values = {_("No"), _("Yes")},
            defaultIndex = 1,
            yearFrom = 1910,
            yearTo = 0
        }
    }
    if (commonapi and commonapi.uiparameter) then
        commonapi.uiparameter.modifyTrackCatenary(list, {selectionlist = tdp.trackList})
        tdp.trackWidthList = func.map(tdp.trackList, function(e) return commonapi.repos.track.getByName(e).data.trackDistance end)
    end
    
    return pipe.new * list
end

local normalizeSize = function(size)
    return 
        ((size.lt - size.lb):cross(size.rb - size.lb).z < 0 )
        and size
        or {
            lt = size.rt,
            lb = size.rb,
            rt = size.lt,
            rb = size.lb
        }
end

tdp.fitModel2D = function(w, h)
    return function(fitTop, fitLeft)
        return function(size)
            local size = normalizeSize(size)
            local s = {
                coor.xyz(0, 0),
                coor.xyz(fitLeft and w or -w, 0),
                coor.xyz(0, fitTop and -h or h),
            }
            
            local t = fitTop and
                {
                    fitLeft and size.lt or size.rt,
                    fitLeft and size.rt or size.lt,
                    fitLeft and size.lb or size.rb,
                } or {
                    fitLeft and size.lb or size.rb,
                    fitLeft and size.rb or size.lb,
                    fitLeft and size.lt or size.rt,
                }
            
            local mX = {
                {s[1].x, s[1].y, 1},
                {s[2].x, s[2].y, 1},
                {s[3].x, s[3].y, 1},
            }
            
            local mU = {
                t[1].x, t[1].y, 1,
                t[2].x, t[2].y, 1,
                t[3].x, t[3].y, 1,
            }
            
            local dX = coor.det(mX)
            
            local miX = coor.minor(mX)
            local mXI = func.mapFlatten(func.seq(1, 3),
                function(l)
                    return func.seqMap({1, 3}, function(c)
                        return ((l + c) % 2 == 0 and 1 or -1) * coor.det(miX(c, l)) / dX
                    end)
                end)
            
            local function mul(m1, m2)
                local m = function(line, col)
                    local l = (line - 1) * 3
                    return m1[l + 1] * m2[col + 0] + m1[l + 2] * m2[col + 3] + m1[l + 3] * m2[col + 6]
                end
                return {
                    m(1, 1), m(1, 2), m(1, 3),
                    m(2, 1), m(2, 2), m(2, 3),
                    m(3, 1), m(3, 2), m(3, 3),
                }
            end
            
            local mXi = mul(mXI, mU)
            
            return coor.I() * {
                mXi[1], mXi[2], 0, mXi[3],
                mXi[4], mXi[5], 0, mXi[6],
                0, 0, 1, 0,
                mXi[7], mXi[8], 0, mXi[9]
            }
        end
    end
end

tdp.fitModel = function(w, h)
    return function(fitTop, fitLeft)
        return function(size)
            local size = normalizeSize(size)
            local s = {
                coor.xyz(0, 0, 0),
                coor.xyz(fitLeft and w or -w, 0, 0),
                coor.xyz(0, fitTop and -h or h, 0),
                coor.xyz(0, 0, -1)
            }
            
            local t = fitTop and
                {
                    fitLeft and size.lt or size.rt,
                    fitLeft and size.rt or size.lt,
                    fitLeft and size.lb or size.rb,
                } or {
                    fitLeft and size.lb or size.rb,
                    fitLeft and size.rb or size.lb,
                    fitLeft and size.lt or size.rt,
                }
            
            local mX = {
                {s[1].x, s[1].y, s[1].z, 1},
                {s[2].x, s[2].y, s[2].z, 1},
                {s[3].x, s[3].y, s[3].z, 1},
                {s[4].x, s[4].y, s[4].z, 1}
            }
            
            local mU = {
                t[1].x, t[1].y, t[1].z, 1,
                t[2].x, t[2].y, t[2].z, 1,
                t[3].x, t[3].y, t[3].z, 1,
                t[1].x, t[1].y, t[1].z - 1, 1
            }
            
            local dX = coor.det(mX)
            
            local miX = coor.minor(mX)
            local mXI = func.mapFlatten(func.seq(1, 4),
                function(l)
                    return func.seqMap({1, 4}, function(c)
                        return ((l + c) % 2 == 0 and 1 or -1) * coor.det(miX(c, l)) / dX
                    end)
                end)
            
            return coor.I() * mXI * mU
        end
    end
end


tdp.buildCoors = function(numTracks, groupSize, config)
    config = config or {
        trackWidth = station.trackWidth,
        wallWidth = 0.5
    }
    local function builder(xOffsets, uOffsets, baseX, nbTracks)
        local function caller(n)
            return builder(
                xOffsets + func.seqMap({1, n}, function(n) return baseX - 0.5 * config.trackWidth + n * config.trackWidth end),
                uOffsets + {baseX + n * config.trackWidth + 0.5 * config.wallWidth},
                baseX + n * config.trackWidth + config.wallWidth,
                nbTracks - n)
        end
        if (nbTracks == 0) then
            local offset = function(o) return o - baseX * config.wallWidth end
            return
                {
                    tracks = xOffsets * pipe.map(offset),
                    walls = uOffsets * pipe.map(offset)
                }
        elseif (nbTracks < groupSize) then
            return caller(nbTracks)
        else
            return caller(groupSize)
        end
    end
    return builder(pipe.new, pipe.new * {0.5 * config.wallWidth}, config.wallWidth, numTracks)
end

tdp.normalizeRad = function(rad)
    return (rad < pi * -0.5) and tdp.normalizeRad(rad + pi * 2) or rad
end

tdp.generateArc = function(arc)
    local toXyz = function(pt) return coor.xyz(pt.x, pt.y, 0) end
    
    local extArc = arc:extendLimits(5)
    
    local sup = toXyz(arc:pt(arc.sup))
    local inf = toXyz(arc:pt(arc.inf))
    local mid = toXyz(arc:pt(arc.mid))
    
    local vecSup = arc:tangent(arc.sup)
    local vecInf = arc:tangent(arc.inf)
    local vecMid = arc:tangent(arc.mid)
    
    local supExt = toXyz(extArc:pt(extArc.sup))
    local infExt = toXyz(extArc:pt(extArc.inf))
    
    return {
        {inf, mid, vecInf, vecMid},
        {mid, sup, vecMid, vecSup},
        {infExt, inf, extArc:tangent(extArc.inf), vecInf},
        {sup, supExt, vecSup, extArc:tangent(extArc.sup)},
    }
end


tdp.fArcs = function(offsets, rad, r)
    return pipe.new
        * offsets
        * function(o) return r > 0 and o or o * pipe.map(pipe.neg()) * pipe.rev() end
        * pipe.map(function(x) return
            func.with(
                arc.byOR(
                    coor.xyz(r, 0, 0) .. coor.rotZ(rad),
                    abs(r) - x
                ), {xOffset = r > 0 and x or -x})
        end)
        * function(a) return r > 0 and a or a * pipe.rev() end
end

tdp.makeFn = function(model, fitModel, w, mPlace, length)
    m = m or coor.I()
    length = length or 5
    local fitTopLeft = fitModel(true, true)
    local fitBottomRight = fitModel(false, false)
    return function(obj)
        local coordsGen = arc.coords(obj, length)
        local inner = obj + (- w * 0.5)
        local outer = obj + (w * 0.5)
        local function makeModel(seq, scale)
            return pipe.new * func.map(func.interlace(seq, {"i", "s"}), 
            function(rad)
                return {
                    station.newModel(model .. "_tl.mdl",
                    mPlace(fitTopLeft, inner, outer, rad.i, rad.s)
                ),
                    station.newModel(model .. "_br.mdl",
                    mPlace(fitBottomRight, inner, outer, rad.i, rad.s)
                )
            }
            end) * pipe.flatten()
        end
        return {
            makeModel(coordsGen(tdp.normalizeRad(obj.inf), tdp.normalizeRad(obj.mid))),
            makeModel(coordsGen(tdp.normalizeRad(obj.mid), tdp.normalizeRad(obj.sup)))
        }
    end
end

local generatePolyArcEdge = function(group, from, to)
    return pipe.from(tdp.normalizeRad(group[from]), tdp.normalizeRad(group[to]))
        * arc.coords(group, 5)
        * pipe.map(function(rad) return func.with(group:pt(rad), {z = 0, rad = rad}) end)
end

tdp.generatePolyArc = function(groups, from, to)
    local groupI, groupO = (function(ls) return ls[1], ls[#ls] end)(func.sort(groups, function(p, q) return p.r < q.r end))
    return function(extLon, extLat)
            
            local groupL, groupR = table.unpack(
                pipe.new
                / (groupO + extLat):extendLimits(extLon)
                / (groupI + (-extLat)):extendLimits(extLon)
                * pipe.sort(function(p, q) return p:pt(p.mid).x < q:pt(p.mid).x end)
            )
            return generatePolyArcEdge(groupR, from, to)
                * function(ls) return ls * pipe.range(1, #ls - 1)
                    * pipe.map2(ls * pipe.range(2, #ls),
                        function(f, t) return
                            {
                                f, t,
                                func.with(groupL:pt(t.rad), {z = 0, rad = t.rad}),
                                func.with(groupL:pt(f.rad), {z = 0, rad = f.rad}),
                            }
                        end)
                end
    end
end

function tdp.regularizeRad(rad)
    return rad > pi
        and tdp.regularizeRad(rad - pi)
        or (rad < -pi and tdp.regularizeRad(rad + pi) or rad)
end


function tdp.polyGen(slope)
    return function(wallHeight, refHeight, guidelines, wHeight, fr, to)
        local f = function(s) return s.g and
            tdp.generatePolyArc(s.g, fr, to)(-0.2, 0)
            * pipe.map(pipe.map(s.fz))
            * station.projectPolys(coor.I())
            or {}
        end
        local polyGen = function(l, e, g)
            return wallHeight == 0 and f(e) or (wallHeight > 0 and f(g) or f(l))
        end
        return {
            slot = polyGen(
                {},
                {},
                {g = guidelines.outer, fz = function(p) return coor.transZ(p.y * slope)(p) end}
            ),
            equal = polyGen(
                {},
                refHeight > 0 and {} or {g = guidelines.ref, fz = function(p) return coor.transZ(p.y * slope)(p) end},
                {}
            ),
            less = polyGen(
                {g = guidelines.outer, fz = function(p) return coor.transZ(p.y * slope)(p) end},
                refHeight > 0 and {g = guidelines.ref, fz = function(p) return coor.transZ(p.y * slope)(p) end} or {},
                {g = guidelines.outer, fz = function(p) return coor.transZ(p.y * slope + wallHeight)(p) end}
            ),
            greater = polyGen(
                {g = guidelines.outer, fz = function(p) return coor.transZ(p.y * slope - wHeight)(p) end},
                refHeight > 0 and {g = guidelines.ref, fz = function(p) return coor.transZ(p.y * slope)(p) end} or {},
                refHeight >= 0 and {g = guidelines.outer, fz = function(p) return coor.transZ(p.y * slope)(p) end} or
                {g = guidelines.outer, fz = function(p) return coor.transZ(p.y * slope - wHeight + wallHeight)(p) end}
        )
        }
    end
end


return tdp
