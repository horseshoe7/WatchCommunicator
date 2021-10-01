//
//  JSONSerializable.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 11.06.21.
//

import Foundation


protocol JSONSerializable: Codable {
    init?(data: Data)
    var data: Data? { get }
    
    init?(json: [String: Any]?)
    var asJSON: [String: Any]? { get }
}

extension JSONSerializable {
    init?(data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(Self.self, from: data) else {
            return nil
        }
        self = value
    }
    
    var data: Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return data
    }
    
    var asJSON: [String: Any]? {
        guard let data = self.data else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.mutableContainers, .allowFragments]) as? [String: Any] else {
            return nil
        }
        return json
    }
    
    init?(json: [String: Any]?) {
        guard let validJSON = json else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: validJSON, options: [.fragmentsAllowed, .prettyPrinted]) else {
            return nil
        }
        self.init(data: data)
    }
}
