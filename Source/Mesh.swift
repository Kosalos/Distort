import UIKit
import Metal

let NONE:Int = -1
let DOWN:Int = 0
let RGHT:Int = 1
let MAX_TOUCH:Int = 5
let XSIZE:Int = 60

var YSIZE:Int = 60
var MAX_NODE:Int = 0
var XDISTANCE = Float()
var YDISTANCE = Float()

struct MeshData {   // mesh data not needed by renderer
    var restPos = simd_float3()
    var velocity = simd_float3()
    var link:[Int] = Array(repeating:Int(), count:2)
}

struct TouchData {  // track multiple touches
    var pt = simd_float2()
    var active:Bool = true
    var nodeX:Int = 0
    var nodeY:Int = 0
}

class Mesh {
    var vBuffer:MTLBuffer! = nil
    var iBufferT:MTLBuffer! = nil
    var vData:[TVertex] = []
    var mData:[MeshData] = []
    var touch:[TouchData] = Array(repeating:TouchData(), count:MAX_TOUCH)
    var iDataT = Array<UInt16>()    // indices of triangles
    var restPositionSpeed = Float()
    var deaccelerate = Float()
    var freeze:Bool = false
    let scale:Float = 0.8
    
    func calcIndex(_ x:Int, _ y:Int) -> Int  {
        if x < 0 || x >= XSIZE || y < 0 || y >= YSIZE { return NONE }
        return y * XSIZE + x
    }
    
    //MARK: -
    
    func update() {
        if vData.count == 0 { return } // haven't initialized yet
        if freeze { return }
        
        // adjust nodes to follow touch positions
        for i in 0 ..< MAX_TOUCH {
            if !touch[i].active { continue }
            
            // nodes surrounding touched node are aimed towards respective offset from it (with force diminishing with distance)
            var ratio = Float()
            for x in -XSIZE ... XSIZE {
                for y in -YSIZE ... YSIZE {
                    let index = calcIndex(touch[i].nodeX + x, touch[i].nodeY + y)
                    if index == NONE { continue }
                    
                    if x != 0 || y != 0 {
                        ratio = 10.0 / Float(x * x + y * y)  // bigger numerator = bigger touch affected region
                        if ratio > 1 { ratio = 1 }
                    }
                    else {
                        ratio = 1
                    }
                    
                    vData[index].pos.x += ((touch[i].pt.x + Float(x) * XDISTANCE) - vData[index].pos.x) * ratio
                    vData[index].pos.y += ((touch[i].pt.y + Float(y) * YDISTANCE) - vData[index].pos.y) * ratio
                }
            }
        }
        
        // Home:  aim velocity toward resting position
        for i in 0 ..< MAX_NODE {
            mData[i].velocity.x -= restPositionSpeed * (vData[i].pos.x - mData[i].restPos.x);
            mData[i].velocity.y -= restPositionSpeed * (vData[i].pos.y - mData[i].restPos.y);
        }
        
        // Constraint: aim velocitys so as to maintain constraint distances
        var constraint = simd_float3(0,0,0)
        var actual = Float()
        var desired = Float()
        
        for nodeIndex1 in 0 ..< MAX_NODE {
            for j in DOWN ... RGHT { // all possible links to this node
                let nodeIndex2 = mData[nodeIndex1].link[j]
                if nodeIndex2 == NONE { continue }
                
                constraint = vData[nodeIndex1].pos - vData[nodeIndex2].pos
                actual = length(constraint)
                if actual == 0 { continue }
                
                desired = j == RGHT ? XDISTANCE : YDISTANCE
                constraint *= 0.005 * (desired - actual) / actual
                
                mData[nodeIndex1].velocity += constraint
                mData[nodeIndex2].velocity -= constraint
            }
        }
        
        // Deaccelerate: apply velocity to position, deaccelerate
        for i in 0 ..< MAX_NODE {
            vData[i].pos += mData[i].velocity
            mData[i].velocity *= deaccelerate
        }
        
        updateVBuffer()
    }
    
    //MARK: -
    // map touch point to 0 ... 1
    func mapPoint(_ pt:CGPoint) -> simd_float2 {
        var ans = simd_float2()
        ans.x =     Float(pt.x / vc.view.frame.width)
        ans.y = 1 - Float(pt.y / vc.view.frame.height) // flip Y coord
        return ans
    }
    
    func touchMove(_ pg:UIPanGestureRecognizer) {
        for i in 0 ..< pg.numberOfTouches {
            let pt = pg.location(ofTouch:i, in:pg.view)
            if pt.y >= vc.metalView.frame.height { continue }
            
            touch[i].pt = mapPoint(pt)
            
            if !touch[i].active {   // just added this finger
                touch[i].active = true
                
                // set to node closest to touch position
                var d = Float()
                var distance:Float = 9999
                
                for x in 0 ..< XSIZE {
                    for y in 0 ..< YSIZE {
                        let nodeIndex:Int = y * XSIZE + x
                        d = hypotf(touch[i].pt.x - vData[nodeIndex].pos.x,
                                   touch[i].pt.y - vData[nodeIndex].pos.y)
                        if d < distance {
                            distance = d
                            touch[i].nodeX = x
                            touch[i].nodeY = y
                        }
                    }
                }
                
                break
            }
        }
    }
    
    func touchEnd() {
        for i in 0 ..< MAX_TOUCH {
            touch[i].active = false
        }
    }
    
    //MARK: -
    let HMIN:Float = 0.00001   // home speed
    let HMAX:Float = 0.0260
    let DMIN:Float = 0.79      // deaccelerate
    let DMAX:Float = 0.995
    
    func updateHomeSpeed(_ v:Float) { restPositionSpeed = HMIN + (HMAX - HMIN) * v }
    func updateDeaccelerateSpeed(_ v:Float) { deaccelerate = DMIN + (DMAX - DMIN) * v }
    
    //MARK: -
    
    func initialize() {
        // xsize is hardwired
        let h:CGFloat = vc.metalView.frame.height
        let w:CGFloat = vc.metalView.frame.width
        
        YSIZE = Int( CGFloat(XSIZE) * h / w)
        MAX_NODE = XSIZE * YSIZE
        XDISTANCE = Float(1) / Float(XSIZE)
        YDISTANCE = Float(1) / Float(YSIZE)
        vData = Array(repeating:TVertex(), count:MAX_NODE)    // vertices for render
        mData = Array(repeating:MeshData(), count:MAX_NODE)   // meta data
        
        iDataT.removeAll()
        
        let center = Float(XSIZE) * scale / 2
        
        func safeLink(_ index:Int, _ size:Int) -> Int {
            if index < 1 || index > size-1 { return NONE }
            return index
        }
        
        // resting positions, links never change
        var index:Int = 0
        for y in 0 ..< YSIZE {
            for x in 0 ..< XSIZE {
                vData[index].txt.x = Float(x) / Float(XSIZE)
                vData[index].txt.y = Float(1) - Float(y) / Float(YSIZE)
                
                // map whole mesh 0 ... 1
                mData[index].restPos.x = Float(x) / Float(XSIZE-1)
                mData[index].restPos.y = Float(y) / Float(YSIZE-1)
                mData[index].restPos.z = 0
                
                mData[index].link[DOWN] = safeLink(index + XSIZE,YSIZE)
                mData[index].link[RGHT] = safeLink(index + 1,XSIZE)
                
                index += 1
            }
        }
        
        // Triangle index buffer -----------
        for y in 0 ..< YSIZE-1 {
            for x in 0 ..< XSIZE-1 {
                let p1 = UInt16(x + y * XSIZE)
                let p2 = UInt16(x + 1 + y * XSIZE)
                let p3 = UInt16(x + (y+1) * XSIZE)
                let p4 = UInt16(x + 1 + (y+1) * XSIZE)
                
                iDataT.append(p1)
                iDataT.append(p3)
                iDataT.append(p2)
                
                iDataT.append(p2)
                iDataT.append(p3)
                iDataT.append(p4)
            }
        }
        
        iBufferT = gDevice?.makeBuffer(bytes: iDataT, length: iDataT.count * MemoryLayout<UInt16>.size,  options: MTLResourceOptions())
        
        reset()
    }
    
    func updateVBuffer() { vBuffer  = gDevice?.makeBuffer(bytes:vData, length: vData.count * MemoryLayout<TVertex>.size, options: MTLResourceOptions()) }
    
    //MARK: -
    
    func reset() {
        freeze = false
        updateHomeSpeed(0.5)
        updateDeaccelerateSpeed(0.5)
        vc.resetWidgets()
        
        for i in 0 ..< MAX_NODE {
            vData[i].pos = mData[i].restPos
            mData[i].velocity = simd_float3(0,0,0)
        }
        
        for i in 0 ..< MAX_TOUCH {
            touch[i].active = false
        }
        
        updateVBuffer()
    }
    
    //MARK: -
    
    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        if vData.count > 0 {
            renderEncoder.setVertexBuffer(vBuffer, offset: 0, index: 0)
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount:iDataT.count, indexType: MTLIndexType.uint16, indexBuffer: iBufferT!, indexBufferOffset:0)
        }
    }
}


