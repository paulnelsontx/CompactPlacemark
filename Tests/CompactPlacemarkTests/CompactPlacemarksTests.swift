    import XCTest
    import Combine
    import CoreLocation
    @testable import CompactPlacemark

    final class CompactPlacemarksTests: XCTestCase {
        var subscriptions = Set<AnyCancellable>()
        func testLocations() {
            // This is an example of a functional test case.
            // Use XCTAssert and related functions to verify your tests produce the correct
            // results.
            // clear cache first -
            let dallas = CLLocation(latitude: 32.779167, longitude: -96.808889)
            let brisbane = CLLocation(latitude: -27.467778, longitude: 153.028056)
            let istanbul = CLLocation(latitude: 41.013611, longitude: 28.955)
            let montreal = CLLocation(latitude: 45.508889, longitude: -73.553167)
            let parisFrance = CLLocation(latitude: 48.856613, longitude: 2.352222)
            let mexicoCity = CLLocation(latitude: 19.433333, longitude: -99.133333)
            let nairobi = CLLocation(latitude: -1.286389, longitude: 36.817222)
            let shenzen = CLLocation(latitude: 22.5415, longitude: 114.0596)
            let stgeorges = CLLocation(latitude: 12.05, longitude: -61.75)
            let baghdad = CLLocation(latitude: 33.333333, longitude: 44.383333)
            let moscow = CLLocation(latitude: 55.755833, longitude: 37.617222)

            let locations = [dallas, brisbane, istanbul, montreal, parisFrance, mexicoCity, nairobi, shenzen, stgeorges, baghdad, moscow]
            let names = ["dallas", "brisbane", "istanbul", "montreal", "parisFrance", "mexicoCity", "nairobi", "shenzen", "grenada", "baghdad", "moscow"]
            let checks = [("$","", "en_US"), // because it is in the current locale, no currenceCode
                          ("$"," AUD", "en_AU"),  // brisbane
                          ("₺"," TRY", "en_TR"),  // istanbul
                          ("$"," CAD", "en_CA"),  // montreal
                          ("€"," EUR", "en_FR"),  // paris
                          ("$", " MXN", "en_MX"), // mexico
                          ("Ksh\u{00A0}"," KES", "en_KE"),  // nairobi
                          ("¥"," CNY", "en_CN"),  // shenzen
                          ("$"," XCD", "en_GD"),  // grenada
                          ("٣"," IQD", "ckb_IQ"),  // baghdad
                          ("$","", "en_RU"),  // moscow
                ]

            CompactPlacemark.deleteCache()
            var expectations = [XCTestExpectation]()
            var placemarks = [CompactPlacemark]()
            var index = 0
            for location in locations {
                let expect = expectation(description:names[index])
                index += 1
                expectations.append(expect)
                let placemark = CompactPlacemark(location:location)
                placemark.publisher.receive(on: DispatchQueue.main).sink { pm in
                    expect.fulfill()
                }.store(in: &subscriptions)
                placemarks.append(placemark)
            }
            wait(for: expectations, timeout: 30.0)
            for idx in 0..<locations.count {
                let placemark = placemarks[idx]
                let (checkSymbol, checkCode, localeID) = checks[idx]
                // random double:
                
                let price = (Double.random(in: 1.0 ..< 150.0) * 100.0) / 100.0
                let priceString = placemark.price(value: price, significantDigits: 2)
//                print("\(names[idx]): \(priceString)")
                XCTAssert( localeID == placemark.locale?.identifier, "Locale \(placemark.locale?.identifier ?? "X") for \(names[idx]) is incorrect")
                let testLocale = Locale(identifier: localeID)
                let fmt = NumberFormatter()
                fmt.minimumFractionDigits = 2
                fmt.maximumFractionDigits = 2
                fmt.locale = testLocale
                fmt.numberStyle = .currency
                if let testString = fmt.string(from: NSNumber(value:price)) {
                    let check = testString + checkCode
                    XCTAssert(check == priceString, "test \(check) is not result \(priceString) for \(names[idx])")
                    XCTAssert(placemark.locale != nil, "Placemark for \(names[idx]) has no locale")
                    if let pmarkLocale = placemark.locale {
                        let direction = Locale.characterDirection(forLanguage: localeID)
                        if direction == .rightToLeft || direction == .bottomToTop {
                            if let currencySymbol = pmarkLocale.currencySymbol {
                                let cchars = (currencySymbol + checkCode).unicodeScalars
                                let pchars = priceString.unicodeScalars
                                var priceLast = pchars.index(before:pchars.endIndex)
                                var symLast = cchars.index(before:cchars.endIndex)
                                while cchars[symLast] == pchars[priceLast] {
                                    symLast = cchars.index(before:symLast)
                                    priceLast = pchars.index(before:priceLast)
                                    if symLast == cchars.startIndex {
                                        break
                                    }
                                }
                                XCTAssert( symLast == cchars.startIndex, "currencySymbol does not match for \(names[idx])")
                            }
                        } else {
                            if pmarkLocale.identifier != "en_RU" {
                                XCTAssertTrue(priceString.hasPrefix(checkSymbol), "Prefix symbol incorrect for \(priceString)")
                            }
                        }
                    }
                } else {
                    XCTFail("NumberFormatter failed for locale \(localeID)")
               }
            }
        }
    }
