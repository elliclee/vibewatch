import AppKit
import CoreImage
let input = FileHandle.standardInput.readDataToEndOfFile()
let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(input, forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
let output = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
let cg = CIContext().createCGImage(output, from: output.extent)!
let bitmap = NSBitmapImageRep(cgImage: cg)
FileHandle.standardOutput.write(bitmap.representation(using: .png, properties: [:])!)
