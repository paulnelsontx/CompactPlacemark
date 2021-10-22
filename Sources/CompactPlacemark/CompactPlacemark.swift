//
//  CompactPlacemark.swift
//  Gas Tripper
//
//  Created by Paul Nelson on 8/4/21.
//  Copyright © 2021 Paul W. Nelson, Nelson Logic. All rights reserved.
//

import Foundation
import Combine
import CoreLocation
import Contacts
import os

public class CompactPlacemark : ObservableObject, Identifiable, PacedOperationProtocol {

    public let location : CLLocation
    @Published var placemark : Place
    @Published var locale : Locale?
    private(set) var timestamp : Date
    public let publisher = PassthroughSubject<CompactPlacemark,Never>()
    public var id = UUID().uuidString
    @Published var error : Error?
    private var operation : PacedOperation?
    
    internal static var oslog = OSLog(subsystem: "com.nelsonlogic", category: "CompactPlacemark")

    public var name : String { placemark.name }
    public var thoroughfare : String { placemark.thoroughfare }
    public var subLocality : String { placemark.subLocality }
    public var locality : String { placemark.locality }
    public var subAdministrativeArea : String { placemark.subAdministrativeArea }
    public var administrativeArea : String { placemark.administrativeArea }
    public var postalCode : String { placemark.postalCode }
    public var country : String { placemark.country }
    public var isoCountryCode : String { placemark.isoCountryCode }
    public var currencyCode : String {
        var value: String? = locale?.currencyCode
        if value == nil {
            value = Locale.current.currencyCode
        }
        return value ?? ""
    }
    public var currencySymbol : String {
        var value: String? = locale?.currencySymbol
        if value == nil {
            value = Locale.current.currencySymbol
        }
        return value ?? ""
    }
    public var volumeConversion : Double {
        let fuelInfo = CompactFuelIndex.lookup(isoCode: placemark.isoCountryCode)
        return fuelInfo.conversion
    }
    public var quantityCode : String {
        if placemark.isoCountryCode.isEmpty, let rc = self.locale?.regionCode {
            let fuelInfo = CompactFuelIndex.lookup(isoCode: rc)
            return fuelInfo.labelShort
        }
        let fuelInfo = CompactFuelIndex.lookup(isoCode: placemark.isoCountryCode)
        return fuelInfo.labelShort
    }
    public var quantityLabel : String {
        if placemark.isoCountryCode.isEmpty, let rc = self.locale?.regionCode {
            let fuelInfo = CompactFuelIndex.lookup(isoCode: rc)
            return fuelInfo.labelLong
        }
        let fuelInfo = CompactFuelIndex.lookup(isoCode: placemark.isoCountryCode)
        return fuelInfo.labelLong
    }
    
    public var usesMetricSystem : Bool {
        let l = locale ?? Locale.current
        return l.usesMetricSystem
    }

    struct Err : Error {
        let localizedDescription : String
        init(_ s: String) {
            localizedDescription = s
        }
    }
    
    static var supportsSecureCoding = true

    public struct Place : Codable {
        let name : String
        let thoroughfare : String
        let subLocality : String
        let locality : String
        let subAdministrativeArea : String
        let administrativeArea : String
        let postalCode : String
        let country : String
        let isoCountryCode : String
        let streetAddress : String

        init(_ strings: [String]) {
            self.name                   = strings.count >= 1 ? strings[0] : ""
            self.thoroughfare           = strings.count >= 2 ? strings[1] : ""
            self.subLocality            = strings.count >= 3 ? strings[2] : ""
            self.locality               = strings.count >= 4 ? strings[3] : ""
            self.subAdministrativeArea  = strings.count >= 5 ? strings[4] : ""
            self.administrativeArea     = strings.count >= 6 ? strings[5] : ""
            self.postalCode             = strings.count >= 7 ? strings[6] : ""
            self.country                = strings.count >= 8 ? strings[7] : ""
            self.isoCountryCode         = strings.count >= 9 ? strings[8] : ""
            self.streetAddress          = strings.count >= 10 ? strings[9] : ""
        }
        
        internal init( _ placemark: CLPlacemark ) {
            self.name = placemark.name ?? ""
            self.thoroughfare = placemark.thoroughfare ?? ""
            self.subLocality = placemark.subLocality ?? ""
            self.locality = placemark.locality ?? ""
            self.subAdministrativeArea = placemark.subAdministrativeArea ?? ""
            self.administrativeArea = placemark.administrativeArea ?? ""
            self.postalCode = placemark.postalCode ?? ""
            self.country = placemark.country ?? ""
            self.isoCountryCode = placemark.isoCountryCode ?? ""
            self.streetAddress = placemark.postalAddress?.street ?? ""
        }
        
        internal init( name: String? = nil,
              thoroughfare : String? = nil,
              subLocality : String? = nil,
              locality : String? = nil,
              subAdministrativeArea : String? = nil,
              administrativeArea : String? = nil,
              postalCode : String? = nil,
              country : String? = nil,
              isoCountryCode : String? = nil,
              streetAddress : String? = nil) {
            self.name                   = name ?? ""
            self.thoroughfare           = thoroughfare ?? ""
            self.subLocality            = subLocality ?? ""
            self.locality               = locality ?? ""
            self.subAdministrativeArea  = subAdministrativeArea ?? ""
            self.administrativeArea     = administrativeArea ?? ""
            self.postalCode             = postalCode ?? ""
            self.country                = country ?? ""
            self.isoCountryCode         = isoCountryCode ?? ""
            self.streetAddress          = streetAddress ?? ""
        }
    }

    private struct Values : Codable {
        let doubles : [Double]
        let strings : [String]
        let timestamp : Date
    }

    public init?( content: Data ) {
        let plist = PropertyListDecoder()
        do {
            let values = try plist.decode(Values.self, from: content)
            let coord = CLLocationCoordinate2D(latitude: values.doubles[0], longitude: values.doubles[1])
            self.location = CLLocation(coordinate: coord, altitude: values.doubles[2],
                                       horizontalAccuracy: values.doubles[3],
                                       verticalAccuracy: values.doubles[4],
                                       timestamp: values.timestamp)
            self.timestamp = values.timestamp
            self.placemark = Place(values.strings)
            if coord.latitude != 0.0, coord.longitude != 0.0,
               self.placemark.isoCountryCode.count == 0 {
                fetch()
            }
            setLocale()
        } catch {
            os_log("%@", log: .default, type: .error,
                   "CompactPlacemark can't init from data: \(error.localizedDescription)")
            return nil
        }
    }
    public init?(_ placemark: CLPlacemark ) {
        guard let loc = placemark.location else {return nil}
        self.location = loc
        self.placemark = Place(placemark)
        self.timestamp = location.timestamp
        var pmLocale : Locale? = nil
        if let cc = placemark.isoCountryCode {
            if let lang = Locale.current.languageCode {
                let ident = "\(lang)_\(cc)"
                if Locale.availableIdentifiers.contains(ident) {
                    pmLocale = Locale(identifier: ident)
                }
            }
            if pmLocale == nil {
                let ident = "en_\(cc)"
                if Locale.availableIdentifiers.contains(ident) {
                    pmLocale = Locale(identifier: ident)
                }
            }
            locale = pmLocale
        } else {
            locale = nil
        }
    }
    public init( location: CLLocation ) {
        self.location = location
        self.timestamp = location.timestamp
        self.locale = Locale.current
        self.placemark = Place([])
        fetch()
    }
    
    public init( latitude: Double, longitude: Double, _ placename : String? = nil) {
        self.location = CLLocation(latitude: latitude, longitude: longitude)
        self.timestamp = Date()
        self.locale = Locale.current
        self.placemark = Place(name:placename)
        fetch()
    }
    
    public init() {
        self.location = CLLocation(latitude: 0, longitude: 0)
        self.timestamp = Date()
        self.locale = Locale.current
        let none = Bundle.module.localizedString(forKey: "NO_LOCATION", value: "xx No Location", table: nil)
        self.placemark = Place(name:none)
    }
    
    static public func deleteCache() {
        CompactPlacemarkCache.shared.deleteCache()
    }
    
    public func price( value: Double, significantDigits : Int = 2 ) -> String {
        let locale = self.locale ?? Locale.current
        let fmt = NumberFormatter()
        fmt.minimumFractionDigits = significantDigits
        fmt.maximumFractionDigits = significantDigits
        fmt.locale = locale
        fmt.numberStyle = .currency
        var priceString : String
        if let str = fmt.string(from: NSNumber(value:value)) {
            priceString = str
        } else {
            let currencyCode = self.currencyCode
            priceString = String(format:"\(currencyCode)%.2f", value)
        }
        if Locale.current.currencyCode != locale.currencyCode {
            if locale.currencyCode != locale.currencySymbol {
                let format = Bundle.module.localizedString(forKey: "PRICE_FORMAT", value: "%1@ %2@", table: nil)
                priceString = String(format:format,
                                   priceString, self.currencyCode)
            }
        }
        return priceString
    }
    public func currency( from: String ) -> Double? {
        let locale = self.locale ?? Locale.current
        let fmt = NumberFormatter()
        fmt.locale = locale
        fmt.numberStyle = .currency
        if let numeric = fmt.number(from: from) {
            return numeric.doubleValue
        }
        return nil
    }
    
    public func numeric( value: Double, significantDigits : Int = 2 ) -> String {
        let locale = self.locale ?? Locale.current
        let fmt = NumberFormatter()
        fmt.minimumFractionDigits = significantDigits
        fmt.maximumFractionDigits = significantDigits
        fmt.locale = locale
        var valueString : String
        if let str = fmt.string(from: NSNumber(value:value)) {
            valueString = str
        } else {
            if significantDigits == 2 {
                valueString = String(format:"%.2f", value)
            } else if significantDigits == 3 {
                valueString = String(format:"%.3f", value)
            } else {
                valueString = String(format:"%f", value)
            }
        }
        return valueString
    }

    public func cancel() {
        if let op = operation {
            op.cancel()
            self.operation = nil
        }
    }

    private func fetch() {
        if let place = CompactPlacemarkCache.shared.get(self) {
            self.placemark = place
            setLocale()
        } else {
            let op = PacedOperation(paced: self)
            self.operation = op
            op.name = self.placemark.name
            PacedOperationQueue.shared.add(op)
        }
    }
    
    public func resetCache() {
        CompactPlacemarkCache.shared.reset(self)
        fetch()
    }
    
    private func setLocale() {
        if self.placemark.isoCountryCode.count > 0 {
            var pmLocale : Locale? = nil
            if let lang = Locale.current.languageCode {
                let ident = "\(lang)_\(self.placemark.isoCountryCode)"
                if Locale.availableIdentifiers.contains(ident) {
                    pmLocale = Locale(identifier: ident)
                }
            }
            if pmLocale == nil {
                let ident = "en_\(self.placemark.isoCountryCode)"
                if Locale.availableIdentifiers.contains(ident) {
                    pmLocale = Locale(identifier: ident)
                }
            }
            self.locale = pmLocale
        } else {
            self.locale = nil
        }
    }
    
    public func encoded() -> Data? {
        let doubles = [
            self.location.coordinate.latitude,
            self.location.coordinate.longitude,
            self.location.altitude,
            self.location.horizontalAccuracy,
            self.location.verticalAccuracy
        ]
        let strings = [
            self.placemark.name,
            self.placemark.thoroughfare,
            self.placemark.subLocality,
            self.placemark.locality,
            self.placemark.subAdministrativeArea,
            self.placemark.administrativeArea,
            self.placemark.postalCode,
            self.placemark.country,
            self.placemark.isoCountryCode
        ]
        let v = Values(doubles:doubles, strings:strings, timestamp:self.timestamp)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        do {
            let content = try encoder.encode(v)
            return content
        } catch {
            os_log("%@", log: .default, type: .error,
                   "CompactPlacemark can't decode \(error.localizedDescription)")
            return nil
        }
    }
    
    public var address : String {
        var addr = ""
        if placemark.thoroughfare.count > 0 {
            addr += placemark.thoroughfare
        }
        if placemark.locality.count > 0 {
            if addr.count > 0 {
                addr += ", "
            }
            addr += placemark.locality
        }
        if placemark.administrativeArea.count > 0 {
            if addr.count > 0 {
                addr += ", "
            }
            addr += placemark.administrativeArea
        }
        if placemark.postalCode.count > 0 {
            addr += " \(placemark.postalCode)"
        }
        if placemark.isoCountryCode.count > 0 {
            addr += " \(placemark.isoCountryCode)"
        }
        return addr
    }
    
    public var streetAddress : String {
        var addr = ""
        if placemark.streetAddress.count > 0 {
            addr += placemark.streetAddress
        } else if placemark.thoroughfare.count > 0 {
            addr += placemark.thoroughfare
        }
        if placemark.locality.count > 0 {
            if addr.count > 0 {
                addr += ", "
            }
            addr += placemark.locality
        }
        if placemark.administrativeArea.count > 0 {
            if addr.count > 0 {
                addr += ", "
            }
            addr += placemark.administrativeArea
        }
        if placemark.postalCode.count > 0 {
            addr += " \(placemark.postalCode)"
        }
        if placemark.isoCountryCode.count > 0 {
            addr += " \(placemark.isoCountryCode)"
        }
        return addr
    }

    var retries : UInt32 = 0
    
    private func processPlacemarks(_ placemarks: [CLPlacemark] ) {
        var theLocale : Locale?
        var thePlacemark : CLPlacemark?
        var localeName = Locale.current.identifier
        let currentLanguage = Locale.current.languageCode ?? "en"
        var countryCode : String?
        // this is overkill, but try to find a locale for the placemark in user's language
        for placemark in placemarks {
            if let country = placemark.isoCountryCode {
                countryCode = country
                let localeName = currentLanguage + "_" + country
                if Locale.availableIdentifiers.contains(localeName) {
                    theLocale = Locale(identifier: localeName)
                    thePlacemark = placemark
                    break
                }
            }
        }
        for placemark in placemarks {
            if let country = placemark.isoCountryCode {
                countryCode = country
                localeName = "en" + "_" + country
                if Locale.availableIdentifiers.contains(localeName) {
                    theLocale = Locale(identifier: localeName)
                    thePlacemark = placemark
                    break
                }
            }
        }
        if theLocale == nil {
            if let cc = countryCode {
                let match = "_" + cc
                for identifier in Locale.availableIdentifiers {
                    if identifier.hasSuffix(match) {
                        theLocale = Locale(identifier:identifier)
                        break
                    }
                }
            }
            if theLocale == nil {
                theLocale = Locale.current
            }
        }
        if let pmark = thePlacemark {
            self.placemark = Place(pmark)
            CompactPlacemarkCache.shared.put(self)
        }
        self.locale = theLocale
        self.publisher.send(self)
    }
    
    private func processReverseError( _ error : Error ) {
        var shouldPublish = false
//        print("reverse error\n")
        if let err = error as? CLError {
            if err.code == CLError.Code.network {
                // try again?
                self.retries += 1
                if self.retries < 4  {
                    // back off
                    let op = PacedOperation(paced: self, delayMultiplier: self.retries)
                    op.name = self.placemark.name
                    PacedOperationQueue.shared.add(op, delayMultiplier: self.retries)
                    return
                }
                // some other error
            }
            self.error = error
            shouldPublish = true
        } else {
            self.error = error
            shouldPublish = true
        }
        if shouldPublish {
            self.publisher.send(self)
        }
    }
    
    internal func pacedPerform(op: PacedOperation) {
        let geocoder = CLGeocoder()
        os_log("%@", log: .default, type: .debug,"CompactPlacemark.pacedPerform looking up \(location.coordinate.latitude),\(location.coordinate.longitude)" )
        geocoder.reverseGeocodeLocation(self.location) { placemarks, error in
            if let err = error {
                self.processReverseError(err)
            } else if let pms = placemarks {
//                print("reverse \(self.placemark.name) ok")
                self.processPlacemarks(pms)
            }
        }
        op.complete()
    }
}

internal class CompactPlacemarkCache {
    static private var _shared : CompactPlacemarkCache? = nil
    static public var shared : CompactPlacemarkCache {
        if _shared == nil {
            _shared = CompactPlacemarkCache()
        }
        return _shared!
    }
    private let cacheDirectory : URL?
    init() {
        let fm = FileManager.default
        do {
            let cacheDir = try fm.url(for: .cachesDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
            if let ident = Bundle.main.bundleIdentifier {
                let bundleURL = URL(fileURLWithPath: ident, relativeTo: cacheDir)
                let cacheDir = URL(fileURLWithPath: "placemarks", relativeTo: bundleURL)
                
//                do { try fm.removeItem(at: cacheDir) } catch { }
                
                var isDir : ObjCBool = false
                if !fm.fileExists(atPath: cacheDir.path, isDirectory: &isDir) {
                    let newPerms = [FileAttributeKey.posixPermissions:NSNumber(value:0x1ed)]

                    try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: newPerms)
                } else {
                    do {
                        try fm.setAttributes([FileAttributeKey.posixPermissions:NSNumber(value:0x1ed)], ofItemAtPath: cacheDir.path)
                    } catch {
                        if let nserr = error as NSError? {
                            os_log("%@", log: .default, type: .error,"CompactPlacemarkCache.init cant set permissionss \(nserr.userInfo)" )
                        }
                    }
                }
                cacheDirectory = cacheDir
            } else {
                cacheDirectory = nil
            }
            
        } catch {
            cacheDirectory = nil
        }
    }
    
    public func deleteCache() {
        if let dir = cacheDirectory {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: dir,
                                                                    includingPropertiesForKeys: nil,
                                                                    options: [])
                for item in files {
                    do {
                        try FileManager.default.removeItem(at: item)
                    } catch {
                    }
                }
            } catch {
            }
        }
    }
    
    func filename( placemark: CompactPlacemark ) -> URL? {
        guard let cachedir = cacheDirectory else {return nil}
        let filename = "pm_\(placemark.location.coordinate.latitude)_\(placemark.location.coordinate.longitude).pmrk"
        let fileURL = URL(fileURLWithPath: filename, relativeTo: cachedir)
        return fileURL
    }
    
    public func put(_ placemark:CompactPlacemark) {
        if let file = filename(placemark: placemark) {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            do {
                let content = try encoder.encode(placemark.placemark)
                try content.write(to: file)
            } catch {
                os_log("%@", log: .default, type: .error,
                       "CompactPlacemarkCache can't decode \(error.localizedDescription)")
            }
        }
    }
    public func get(_ placemark:CompactPlacemark) -> CompactPlacemark.Place? {
        do {
            if let file = filename(placemark: placemark) {
                let content = try Data(contentsOf:file)
                let plist = PropertyListDecoder()
                    let place = try plist.decode(CompactPlacemark.Place.self, from: content)
                    return place
            }
        } catch {
            
        }
        return nil
    }
    
    public func reset(_ placemark:CompactPlacemark) {
        do {
            if let file = filename(placemark: placemark) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            // ignore errors
        }
    }
}


internal struct CompactFuelIndex {
    let conversion : Double // multiply for liters, divide for locale
    let labelLong: String
    let labelShort: String
    
    static var index : Dictionary<String,Dictionary<String,Any>>?
    
    init(conversion:Double, long: String, short: String){
        self.conversion = conversion
        self.labelLong = Bundle.module.localizedString(forKey:long, value: long, table:nil)
        self.labelShort = Bundle.module.localizedString(forKey:short, value: short, table:nil)
    }
    
    static func lookup(isoCode: String) -> CompactFuelIndex {
        if index == nil {
            if let url = Bundle.module.url(forResource: "gasoline_index", withExtension: "json") {
                do {
                    let contents = try Data(contentsOf:url)
                    if let info = try JSONSerialization.jsonObject(with: contents, options:[]) as? Dictionary<String,Dictionary<String,Any>> {
                        CompactFuelIndex.index = info
                    }
                } catch {
                    os_log("%@", log: .default, type: .error,
                           "Cant load gasoline_index.json: \(error.localizedDescription)")
                }
            }
        }
        if let idx = index {
            var key : String
            if isoCode.isEmpty {
                if let rc = Locale.current.regionCode {
                    key = rc
                } else {
                    key = ""
                }
            } else {
                key = isoCode
            }
            if let info = idx[key],
               let factor = info["factor"] as? Double,
               let long = info["long"] as? String,
               let short = info["short"] as? String {
                return CompactFuelIndex(conversion:factor, long:long, short:short)
            }
        }
        // all others are metric
        return CompactFuelIndex(conversion: 1.0,
                                long: "FUEL_QUANTITY_METRIC_LONG",
                                short: "FUEL_QUANTITY_METRIC_SHORT")
    }
}
