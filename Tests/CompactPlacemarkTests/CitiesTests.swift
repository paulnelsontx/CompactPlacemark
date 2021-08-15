//
//  PlacemarkTests.swift
//  Gas TripperTests
//
//  Created by Paul Nelson on 8/5/21.
//  Copyright © 2021 Paul W. Nelson, Nelson Logic. All rights reserved.
//

import XCTest
import Combine
@testable import CompactPlacemark

class CitiesTests: XCTestCase {
    var subscriptions = Set<AnyCancellable>()
    var cities : [Any]?
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        do {
            let bundle = Bundle(for: CitiesTests.self)
            let citiesURL = bundle.url(forResource: "test_cities", withExtension: "json")
            if let url = citiesURL {
                let citiesData = try Data(contentsOf: url)
                let info = try JSONSerialization.jsonObject(with: citiesData, options: [])
                if let items = info as? [Any]  {
                    print("\(items.count) cities")
                    cities = items
                }
            }
        } catch {
            print("setup fail: \(error.localizedDescription)")
        }
        CompactPlacemark.deleteCache()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCityLookup() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        var placemarks = [CompactPlacemark]()
        var expectations = [XCTestExpectation]()
        var count = 100
        if let items = cities {
            for item in items {
                if let city = item as? [String:Any], let name = city["city"] as? String,
                   let lat = city["lat"] as? Double,
                   let long = city["long"] as? Double {
                    let expect = expectation(description:"placemark \(name)")
                    expectations.append(expect)
                    let placemark = CompactPlacemark(latitude: lat, longitude: long)
                    placemarks.append(placemark)
                    placemark.publisher.receive(on: DispatchQueue.main).sink { pm in
                        expect.fulfill()
                        print("\(pm.placemark.name), \(pm.placemark.postalCode)")
                    }.store(in: &subscriptions)
                }
                count -= 1
                if count <= 0 {
                    break
                }
            }
            // 40 cities should take about 1 minutes
            wait(for:expectations, timeout:12.0*60.0)
            print("OK")
        }
    }

//    func testPerformanceExample() throws {
//        // This is an example of a performance test case.
//        self.measure {
//            // Put the code you want to measure the time of here.
//        }
//    }

}
