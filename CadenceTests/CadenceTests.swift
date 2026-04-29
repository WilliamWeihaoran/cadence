//
//  CadenceTests.swift
//  CadenceTests
//
//  Created by William Wei on 3/26/26.
//

import Testing
import Foundation
@testable import Cadence

struct CadenceTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func appleAccountDefaultsStorageRoundTripsProfile() throws {
        let suiteName = "CadenceTests.appleAccount.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let storage = AppleAccountDefaultsStorage(defaults: defaults)
        let signedInAt = Date(timeIntervalSince1970: 1_777_777)
        let profile = AppleAccountProfile(
            userIdentifier: "apple-user-1",
            email: "person@example.com",
            givenName: "Ada",
            familyName: "Lovelace",
            signedInAt: signedInAt
        )

        storage.saveProfile(profile)

        #expect(storage.loadProfile() == profile)

        storage.clearProfile()

        #expect(storage.loadProfile() == nil)
    }

    @Test func appleAccountProfileMergePreservesFirstGrantFields() {
        let existing = AppleAccountProfile(
            userIdentifier: "apple-user-1",
            email: "person@example.com",
            givenName: "Ada",
            familyName: "Lovelace",
            signedInAt: Date(timeIntervalSince1970: 100)
        )
        let refreshedAt = Date(timeIntervalSince1970: 200)

        let merged = AppleAccountProfileMerge.merged(
            existing: existing,
            userIdentifier: "apple-user-1",
            email: nil,
            givenName: "",
            familyName: nil,
            signedInAt: refreshedAt
        )

        #expect(merged.email == "person@example.com")
        #expect(merged.givenName == "Ada")
        #expect(merged.familyName == "Lovelace")
        #expect(merged.signedInAt == refreshedAt)
    }

    @Test func appleSignInEntitlementParsingRecognizesDefaultValue() {
        let configured = AppleSignInEntitlementStatus.parsed(from: ["Default"])
        let missing = AppleSignInEntitlementStatus.parsed(from: nil)

        #expect(configured.isConfigured)
        #expect(configured.title == "Available")
        #expect(missing.isConfigured == false)
        #expect(missing.title == "Missing")
    }

}
