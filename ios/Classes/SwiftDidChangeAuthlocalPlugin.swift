import Flutter
import UIKit

public class SwiftDidChangeAuthlocalPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "did_change_authlocal", binaryMessenger: registrar.messenger())

      
    let instance = SwiftDidChangeAuthlocalPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "get_token":
      self.authenticateBiometric { data,code in  
      
      switch code { 
         case 200:
          result(data)
         case -7:
          result(FlutterError(code:"biometric_invalid",message:"Invalid biometric",details: data as Any))
          default:
          result(FlutterError(code:  "unknow", message: data, details: nil))

      }}
             default:
                result(FlutterMethodNotImplemented)

      
    }
  }


    func authenticateBiometric(complete : @escaping (String?, Int?) -> Void){
        let context = LAContext()
             
             var authError : NSError?
             if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) == false {
                 complete(nil, authError?.code)
                 return
             }
             if let biometricData = context.evaluatedPolicyDomainState {
                 let base64Data = biometricData.base64EncodedData()
                 let stringData = String(data: base64Data, encoding: .utf8)
                 complete(stringData, 200)
             }else {
                 complete(nil, 998)
             }
      }

}
