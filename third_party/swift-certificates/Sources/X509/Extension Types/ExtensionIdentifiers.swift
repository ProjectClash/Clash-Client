 
 
 
 
 
 
 
 
 
 
 
 
 

import SwiftASN1

extension ASN1ObjectIdentifier {
     
    public enum X509ExtensionID {
         
         
        public static let authorityKeyIdentifier: ASN1ObjectIdentifier = [2, 5, 29, 35]

         
         
        public static let subjectKeyIdentifier: ASN1ObjectIdentifier = [2, 5, 29, 14]

         
         
        public static let keyUsage: ASN1ObjectIdentifier = [2, 5, 29, 15]

         
         
        public static let subjectAlternativeName: ASN1ObjectIdentifier = [2, 5, 29, 17]

         
         
        public static let basicConstraints: ASN1ObjectIdentifier = [2, 5, 29, 19]

         
         
        public static let nameConstraints: ASN1ObjectIdentifier = [2, 5, 29, 30]

         
         
        public static let extendedKeyUsage: ASN1ObjectIdentifier = [2, 5, 29, 37]

         
         
        public static let authorityInformationAccess: ASN1ObjectIdentifier = [1, 3, 6, 1, 5, 5, 7, 1, 1]
    }
}
