local func = require "track_design_patterns/func"
local pipe = require "track_design_patterns/pipe"
local coor = require "track_design_patterns/coor"

local abs = math.abs
local unpack = table.unpack

local stationlib = {
    platformWidth = 5,
    trackWidth = 5,
    segmentLength = 20,
    infi = 1e8
}

stationlib.newModel = function(m, ...)
    return {
        id = m,
        transf = coor.mul(...)
    }
end


stationlib.generateTrackGroups = function(xOffsets, length, extra)
    local halfLength = length * 0.5
    extra = extra or {mpt = coor.I(), mvec = coor.I()}
    return func.mapFlatten(xOffsets,
        function(xOffset)
            return coor.applyEdges(coor.mul(xOffset.parity, extra.mpt, xOffset.mpt), coor.mul(xOffset.parity, extra.mvec, xOffset.mvec))(
                {
                    {{0, -halfLength, 0}, {0, halfLength, 0}},
                    {{0, 0, 0}, {0, halfLength, 0}},
                    {{0, 0, 0}, {0, halfLength, 0}},
                    {{0, halfLength, 0}, {0, halfLength, 0}},
                })
        end
)
end

stationlib.preBuild = function(totalTracks, baseX, ignoreFst, ignoreLst)
    local groupWidth = stationlib.trackWidth + stationlib.platformWidth
    local function build(nbTracks, baseX, xOffsets, uOffsets)
        if (nbTracks == 0) then
            return xOffsets, uOffsets
        elseif ((nbTracks == 1 and ignoreLst) or (nbTracks == totalTracks and not ignoreFst)) then
            return build(nbTracks - 1, baseX + groupWidth,
                func.concat(xOffsets, {baseX + 0.5 * groupWidth}),
                func.concat(uOffsets, {baseX}))
        elseif (nbTracks == 1 and not ignoreLst) then
            return build(nbTracks - 1, baseX + groupWidth - 0.5 * stationlib.trackWidth,
                func.concat(xOffsets, {baseX}),
                func.concat(uOffsets, {baseX + 0.5 * groupWidth}))
        else return build(nbTracks - 2, baseX + groupWidth + stationlib.trackWidth,
            func.concat(xOffsets, {baseX, baseX + groupWidth}),
            func.concat(uOffsets, {baseX + 0.5 * groupWidth})
        )
        end
    end
    
    return build(totalTracks, baseX, {}, {})
end

stationlib.buildCoors = function(nSeg)
    local groupWidth = stationlib.trackWidth + stationlib.platformWidth
    
    local function buildUIndex(uOffset, ...) return {func.seq(uOffset * nSeg, (uOffset + 1) * nSeg - 1), {...}} end
    
    local function buildGroup(level, baseX, nbTracks, xOffsets, uOffsets, xuIndex)
        local project = function(x, p) return func.map2(x, p, function(offset, parity) return
            {
                mpt = coor.transX(offset) * level.mdr * level.mz,
                mvec = level.mr,
                parity = parity,
                id = level.id,
                x = offset
            }
        end) end
        
        local make = function(params)
            return
                nbTracks - #params.xOffset,
                func.concat(xOffsets, project(params.xOffset, params.xParity)),
                func.concat(uOffsets, project(params.uOffset, {coor.I()})),
                func.concat(xuIndex, {params.xuIndex})
        end
        
        if (nbTracks == 0) then
            return xOffsets, uOffsets, xuIndex
        elseif ((nbTracks == 1 and level.ignoreLst) or (nbTracks == level.nbTracks and not level.ignoreFst)) then
            return buildGroup(level, baseX + groupWidth,
                make({
                    xOffset = {baseX + 0.5 * groupWidth},
                    xParity = {coor.flipY()},
                    uOffset = {baseX},
                    xuIndex = buildUIndex(#uOffsets, {1, #xOffsets + 1})
                })
        )
        elseif (nbTracks == 1 and not level.ignoreLst) then
            return buildGroup(level, baseX + groupWidth - 0.5 * stationlib.trackWidth,
                make({
                    xOffset = {baseX},
                    xParity = {coor.I()},
                    uOffset = {baseX + 0.5 * groupWidth},
                    xuIndex = buildUIndex(#uOffsets, {0, #xOffsets + 1})
                })
        )
        else
            return buildGroup(level, baseX + groupWidth + stationlib.trackWidth,
                make({
                    xOffset = {baseX, baseX + groupWidth},
                    xParity = {coor.I(), coor.flipY()},
                    uOffset = {baseX + 0.5 * groupWidth},
                    xuIndex = buildUIndex(#uOffsets, {0, #xOffsets + 1}, {1, #xOffsets + 2})
                })
        )
        end
    end
    
    local function build(trackGroups, ...)
        if (#trackGroups == 1) then
            local group = unpack(trackGroups)
            return buildGroup(group, group.baseX, group.nbTracks, ...)
        else
            return build(func.range(trackGroups, 2, #trackGroups), build({trackGroups[1]}, ...))
        end
    end
    return build
end

stationlib.noSnap = function(_) return {} end

stationlib.makePlatforms = function(uOffsets, platforms, m)
    local length = #platforms * stationlib.segmentLength
    return func.mapFlatten(uOffsets,
        function(uOffset)
            return func.map2(func.seq(1, #platforms), platforms, function(i, p)
                return stationlib.newModel(p, coor.transY(i * stationlib.segmentLength - 0.5 * (stationlib.segmentLength + length)), uOffset.mpt, m) end
        )
        end)
end

stationlib.makeTerminals = function(xuIndex)
    return func.mapFlatten(xuIndex, function(xu)
        local terminals, xIndices = unpack(xu)
        return func.map(xIndices, function(x)
            local side, track = unpack(x)
            return {
                terminals = func.map(terminals, function(t) return {t, side} end),
                vehicleNodeOverride = track * 4 - 2
            }
        end
    )
    end)
end

stationlib.setHeight = function(result, height)
    local mpt = coor.transZ(height)
    local mvec = coor.I()
    
    local mapEdgeList = function(edgeList)
        edgeList.edges = func.map(edgeList.edges, coor.applyEdge(mpt, mvec))
        return edgeList
    end
    
    result.edgeLists = func.map(result.edgeLists, mapEdgeList)
    
    local mapModel = function(model)
        model.transf = model.transf * mpt
        return model
    end
    
    result.models = func.map(result.models, mapModel)
end

stationlib.faceMapper = function(m)
    return function(face)
        return func.map(face, function(pt) return (coor.tuple2Vec(pt) .. m):toTuple() end)
    end
end

stationlib.toEdge = function(o, vec) return {o:toTuple(), (o + vec):toTuple(), vec:toTuple(), vec:toTuple()} end

local function edgesBuilder(result, o, vec, ...)
    local vecs = {...}
    return #vecs == 0 and result / stationlib.toEdge(o, vec) or edgesBuilder(result / stationlib.toEdge(o, vec), o + vec, ...)
end

stationlib.toEdges = function(o, ...)
    return edgesBuilder(pipe.new, o, ...)
end

local snapNodes = function(edges)
    return edges
        * pipe.mapFlatten(pipe.select("snap"))
        * pipe.flatten()
        * function(ls) return ls * pipe.zip(func.seq(0, #ls - 1), {"snap", "index"}) end
        * pipe.filter(pipe.select("snap"))
        * pipe.map(pipe.select("index"))
end

stationlib.prepareEdges = function(freeNodes) 
    return function(edges)
        return (freeNodes == nil) 
        and {
            edges = {},
            snapNodes = {}
        } or {
            edges = edges * pipe.mapFlatten(pipe.select("edge")) * pipe.map(pipe.map(coor.vec2Tuple)) * coor.make,
            snapNodes = snapNodes(edges),
            freeNodes = freeNodes and func.fold(edges, func.seq(0, #func.mapFlatten(edges, pipe.select("edge")) * 2 - 1), function(f, e) return e.freezenNodes and {} or f end) or {}
        }
    end
end

stationlib.joinEdges = function(edges)
    local function average(op1, op2) return (op1 + op2) * 0.5, (op1 + op2) * 0.5 end
    local fst = function(l) return l[1][1] end
    local lst = function(l) return l[#l][2] end
    local rev = function(l) return pipe.new
        * func.map(l, function(e)
            local f, t, vf, vt = unpack(e)
            return {t, f, -vt, -vf}
        end)
        * pipe.rev()
    end
    local joinEdge = function(l, r)
        local newL = l + {}
        local newR = r + {}
        newL[#l][2], newR[1][1] = average(newL[#l][2], newR[1][1])
        newL[#l][4], newR[1][3] = average(newL[#l][4], newR[1][3])
        return {newL, newR}
    end
    local connect = function(l, r)
        local pattern = {
            {fst, fst, function() return rev(l), r end},
            {fst, lst, function() return rev(l), rev(r) end},
            {lst, fst, function() return l, r end},
            {lst, lst, function() return l, rev(r) end}
        }
        return pipe.new
            * func.map(pattern, function(fns)
                local pl, pr, fadj = unpack(fns)
                return (pl(l) - pr(r)):length2() < 0.1
                    and joinEdge(fadj())
                    or nil
            end)
            * pipe.filter(pipe.noop())
            * function(ls) return #ls == 0 and {l, r} or ls[1] end
    end
    
    local function join(result, fst, snd, ...)
        local function fn(...)
            local newEdges = connect(fst.edge, snd.edge)
            return join(
                result / (func.with(fst, {edge = newEdges[1]})),
                func.with(snd, {edge = newEdges[2]}),
                ...
        )
        end
        return snd and fn(...) or result / fst
    end
    
    return #edges > 1 and join(pipe.new, unpack(edges)) or edges
end

stationlib.mergeEdges = function(edges)
    return {
        edge = pipe.new * func.map(edges, pipe.select("edge")) * pipe.flatten(),
        snap = pipe.new * func.map(edges, pipe.select("snap")) * pipe.flatten(),
        freezenNodes = func.fold(edges, false, function(f, e) return e.freezenNodes or f end)
    }
end

stationlib.fusionEdges = function(edges)
    local function transpose(result, ls, ...)
        return ls
            and (result
            and transpose(result * pipe.map2(ls, function(current, new) return current / new end),
                ...)
            or transpose(ls * pipe.map(function(_) return pipe.new end), ls, ...)
            )
            or result
    end
    return #edges > 0
        and transpose(nil, unpack(edges))
        * pipe.map(stationlib.joinEdges)
        * function(ls) return transpose(nil, unpack(ls)) end
        or {}
end


stationlib.basePt = pipe.new * {
    coor.xyz(-0.5, -0.5, 0),
    coor.xyz(0.5, -0.5, 0),
    coor.xyz(0.5, 0.5, 0),
    coor.xyz(-0.5, 0.5, 0)
}

stationlib.surfaceOf = function(size, center, ...)
    local tr = {...}
    return stationlib.basePt
        * pipe.map(function(f) return (f .. coor.scale(size) * coor.trans(center)) end)
        * pipe.map(function(f) return func.fold(tr, f, function(v, m) return v .. m end) end)
        * pipe.map(function(v) return v:toTuple() end)
end

local applyResult = function(mpt, mvec, mirrored)
    mirrored = mirrored or false
    return function(result)
        local mapEdgeList = function(edgeList)
            return func.with(edgeList, {edges = func.map(edgeList.edges, coor.applyEdge(mpt, mvec))})
        end
        
        local mapModel = function(model) return func.with(model, {transf = coor.I() * model.transf * mpt}) end
        
        local mapTerrainList = function(ta)
            local mapTerrain = function(t) return (coor.tuple2Vec(t) .. mpt):toTuple() end
            local mapFaces = function(faces) return (mirrored and func.rev or func.nop)(func.map(faces, mapTerrain)) end
            return func.with(ta, {faces = func.map(ta.faces, mapFaces)})
        end
        
        local mapGroundFaces = function(gf)
            return func.with(gf, {face = func.map(mirrored and func.rev(gf.face) or gf.face, function(f) return (coor.tuple2Vec(f) .. mpt):toTuple() end)})
        end
        
        return func.with(result,
            {
                edgeLists = result.edgeLists and func.map(result.edgeLists, mapEdgeList) or {},
                models = result.models and func.map(result.models, mapModel) or {},
                terrainAlignmentLists = result.terrainAlignmentLists and func.map(result.terrainAlignmentLists, mapTerrainList) or {},
                groundFaces = result.groundFaces and func.map(result.groundFaces, mapGroundFaces) or {}
            })
    end
end

stationlib.setTransform = function(m)
    return function(result)
        local _, mr, _ = coor.decomposite(m)
        return applyResult(m, mr)(result)
    end
end

stationlib.setRotation = function(rad)
    return function(result)
        local mr = coor.rotZ(rad)
        return applyResult(mr, mr)(result)
    end
end

stationlib.setSlope = function(slope)
    return function(result)
        local mr = coor.rotX(math.atan(slope * 0.001))
        return applyResult(mr, mr)(result)
    end
end

stationlib.setHeight = function(dHeight)
    return function(result)
        local mz = coor.transZ(dHeight)
        return applyResult(mz, coor.I())(result)
    end
end

stationlib.setMirror = function(isMirror)
    return function(result)
        local mf = isMirror and coor.flipX() or coor.I()
        return applyResult(mf, mf, isMirror)(result)
    end
end

stationlib.finalizePoly = function(poly)
    return pipe.new * poly
    * function(p) return ((p[2] - p[1]):cross(p[3] - p[2]).z > 0 and pipe.noop() or pipe.rev())(poly) end
    * function(p) return #p == 4 and abs((p[1] - p[2]):cross(p[3] - p[2]).z) < 0.1 and {p[1], p[3], p[4]} or p end
    * function(p) return #p == 4 and abs((p[2] - p[3]):cross(p[4] - p[3]).z) < 0.1 and {p[1], p[2], p[4]} or p end
    * function(p) return #p == 4 and abs((p[3] - p[4]):cross(p[1] - p[4]).z) < 0.1 and {p[1], p[2], p[3]} or p end
    * function(p) return #p == 4 and abs((p[4] - p[1]):cross(p[2] - p[1]).z) < 0.1 and {p[2], p[3], p[4]} or p end
    * pipe.map(coor.vec2Tuple)
end


function stationlib.projectPolys(mDepth)
    return function(...)
        return pipe.new * func.flatten({...}) * pipe.map(pipe.map(mDepth)) * pipe.map(stationlib.finalizePoly)
    end
end


function stationlib.mergePoly(...)
    local polys = pipe.new * {...}
    local p = {
        equal = polys * pipe.map(pipe.select("equal", {})) * pipe.filter(pipe.noop()) * pipe.flatten(),
        less = polys * pipe.map(pipe.select("less", {})) * pipe.filter(pipe.noop()) * pipe.flatten(),
        greater = polys * pipe.map(pipe.select("greater", {})) * pipe.filter(pipe.noop()) * pipe.flatten(),
        slot = polys * pipe.map(pipe.select("slot", {})) * pipe.filter(pipe.noop()) * pipe.flatten(),
        platform = polys * pipe.map(pipe.select("platform", {})) * pipe.filter(pipe.noop()) * pipe.flatten(),
    }
    
    return
        function(profile)
            profile = profile or {}
            
            return pipe.new * {
                {
                    type = "LESS",
                    faces = p.less,
                    slopeLow = profile.less or 0.75,
                    slopeHigh = profile.less or 0.75,
                },
                {
                    type = "GREATER",
                    faces = p.greater,
                    slopeLow = profile.greater or 0.75,
                    slopeHigh = profile.greater or 0.75,
                },
                {
                    type = "EQUAL",
                    faces = p.equal,
                    slopeLow = profile.equal or 0.75,
                    slopeHigh = profile.equal or 0.755,
                },
                {
                    type = "LESS",
                    faces = p.slot,
                    slopeLow = profile.slot or stationlib.infi,
                    slopeHigh = profile.slot or  stationlib.infi,
                },
                {
                    type = "GREATER",
                    faces = p.platform,
                    slopeLow = profile.platform or stationlib.infi,
                    slopeHigh = profile.platform or stationlib.infi,
                },
            }
            * pipe.filter(function(e) return #e.faces > 0 end)
        end
end

stationlib.pureParams = function(pa)
    local params = {}
    for key,value in pairs(pa) do
        if (key ~= "seed") then
            params[key] = value
        end
    end
    return params
end

stationlib.joinArcs = function(arc)
    local function average(op1, op2) return (op1 + op2) * 0.5, (op1 + op2) * 0.5 end
    local joinEdge = function(l, r)
        local newL = l
        local newR = r
        newL[2], newR[1] = average(newL[2], newR[1])
        newL[4], newR[3] = average(newL[4], newR[3])
        return newL, newR
    end
    
    local function join(result, fst, snd, ...)
        local function fn(...)
            local newL, newR = joinEdge(fst, snd)
            return join(result / newL, newR, ...)
        end
        return snd and fn(...) or result / fst
    end
    return {
        edge = join(pipe.new, unpack(arc.edge)),
        snap = arc.snap,
        freeNodes = arc.freeNodes
    }
end

return stationlib
