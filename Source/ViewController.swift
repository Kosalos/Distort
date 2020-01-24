import UIKit
import MetalKit

var vc:ViewController!

class ViewController: UIViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    var mesh = Mesh()
    var timer = Timer()
    var renderer:Renderer!
    
    @IBOutlet var metalView: MTKView!
    @IBOutlet var s1: UISlider!
    @IBOutlet var s2: UISlider!
    @IBOutlet var freezeSwitch: UISwitch!
    
    @IBAction func freezeChanged(_ sender: UISwitch) {  mesh.freeze = sender.isOn }
    @IBAction func savePicButtonPressed(_ sender: UIButton) { mesh.savePic() }
    
    @IBAction func sliderChanged(_ sender: UISlider) {
        switch sender {
        case s1 : mesh.updateHomeSpeed(sender.value)
        default : mesh.updateDeaccelerateSpeed(sender.value)
        }
    }
    
    @IBAction func resetButtonPressed(_ sender: UIButton) { mesh.reset() }
    
    //MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        
        guard let metalView = metalView else { print("View of Gameview controller is not an MTKView"); exit(0) }
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else { print("Metal is not supported"); exit(0) }
        
        metalView.device = defaultDevice
        metalView.backgroundColor = UIColor.clear
        
        guard let newRenderer = Renderer(metalKitView: metalView) else { print("Renderer cannot be initialized"); exit(0) }
        renderer = newRenderer
        renderer.mtkView(metalView, drawableSizeWillChange: metalView.drawableSize)
        metalView.delegate = renderer
        metalView.framebufferOnly = false
    }
    
    override func viewDidAppear(_ animated: Bool) {
        mesh.initialize()
        timer = Timer.scheduledTimer(timeInterval: 0.05, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)
    }
    
    //MARK: -
    
    @objc func timerHandler() {
        mesh.update()
    }
    
    func resetWidgets() {
        s1.value = 0.5
        s2.value = 0.5
        freezeSwitch.isOn = false
    }
    
    //MARK: -
    
    @IBAction func takePicture() {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.allowsEditing = true
        vc.delegate = self
        present(vc, animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        if let pic = info[UIImagePickerControllerOriginalImage] as? UIImage {
            renderer.updateTexture(pic)
            mesh.reset()
        }
        
        dismiss(animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: false, completion: nil)
    }
    
    //MARK: -
    
    var tCount:Int = 0
    
    @IBAction func panGesture(_ pg:UIPanGestureRecognizer) {
        let nt = pg.numberOfTouches
        if nt == 0 { tCount = 0 }
        if tCount == 0 { tCount = nt }
        if tCount < nt { tCount = nt }                  // adding fingers is okay
        if tCount != nt { mesh.touchEnd(); return }     // removing a finger during gesture stops the session
        
        switch pg.state {
        case .began, .changed : mesh.touchMove(pg)
        case .ended : mesh.touchEnd()
        default : break
        }
    }
   
    override var prefersStatusBarHidden: Bool { return true }
}
