//
//  HelperProtocol.swift
//  JUMP-IN
//

import Foundation

@objc protocol HelperToolProtocol {
    // Version and status info
    func getVersionString(withReply reply: @escaping (String) -> Void)
    func getCurrentTenant(withReply reply: @escaping (String?) -> Void)
    func getCurrentUser(withReply reply: @escaping (String) -> Void)
    func checkToolVersion(version: String, withReply reply: @escaping (Bool) -> Void)
    
    // Tenant operations
    func removeCurrentTenantProfile(withReply reply: @escaping (NSError?) -> Void)
    func backupTenantSettings(withReply reply: @escaping (String?, NSError?) -> Void)
    func updateCompanyPortal(withReply reply: @escaping (NSError?) -> Void)
    func enrollInNewTenant(targetTenant: String, withReply reply: @escaping (NSError?) -> Void)
    func rotateFileVaultKey(withReply reply: @escaping (NSError?) -> Void)
    
    // System checks
    func checkIntuneEnrollment(withReply reply: @escaping (Bool) -> Void)
    func checkFileVaultStatus(withReply reply: @escaping (Bool) -> Void)
    func checkGatekeeperStatus(withReply reply: @escaping (Bool) -> Void)
}

