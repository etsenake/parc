import Foundation

public final class TestDefaults: UserDefaults {
    private let domain: String
    private let lock = NSLock()
    private var values: [String: AnyObject] = [:]

    public init?(_ prefix: String) {
        domain = prefix + UUID().uuidString
        super.init(suiteName: domain)
    }

    deinit {
        if persistentDomain(forName: domain)?.isEmpty == false {
            removePersistentDomain(forName: domain)
        }
    }

    public override func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    public override func set(_ value: Any?, forKey defaultName: String) {
        let stored = value.map(Self.propertyListObject)
        lock.withLock { values[defaultName] = stored }
    }

    private static func propertyListObject(_ value: Any) -> AnyObject {
        if let dictionary = value as? [String: Any] {
            return NSDictionary(dictionary: dictionary.mapValues(propertyListObject))
        }
        if let array = value as? [Any] {
            return NSArray(array: array.map(propertyListObject))
        }
        return value as AnyObject
    }

    public override func set(_ value: Bool, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public override func set(_ value: Int, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public override func set(_ value: Float, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public override func set(_ value: Double, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public override func set(_ url: URL?, forKey defaultName: String) {
        set(url.map { $0 as Any }, forKey: defaultName)
    }

    public override func removeObject(forKey defaultName: String) {
        set(nil as Any?, forKey: defaultName)
    }

    public override func string(forKey defaultName: String) -> String? {
        let value = object(forKey: defaultName)
        return value as? String ?? (value as? NSNumber)?.stringValue
    }

    public override func bool(forKey defaultName: String) -> Bool {
        let value = object(forKey: defaultName)
        return (value as? NSNumber)?.boolValue ?? (value as? NSString)?.boolValue ?? false
    }

    public override func integer(forKey defaultName: String) -> Int {
        let value = object(forKey: defaultName)
        return (value as? NSNumber)?.intValue ?? (value as? NSString)?.integerValue ?? 0
    }

    public override func float(forKey defaultName: String) -> Float {
        let value = object(forKey: defaultName)
        return (value as? NSNumber)?.floatValue ?? (value as? NSString)?.floatValue ?? 0
    }

    public override func double(forKey defaultName: String) -> Double {
        let value = object(forKey: defaultName)
        return (value as? NSNumber)?.doubleValue ?? (value as? NSString)?.doubleValue ?? 0
    }

    public override func array(forKey defaultName: String) -> [Any]? {
        object(forKey: defaultName) as? [Any]
    }

    public override func dictionary(forKey defaultName: String) -> [String: Any]? {
        object(forKey: defaultName) as? [String: Any]
    }

    public override func data(forKey defaultName: String) -> Data? {
        object(forKey: defaultName) as? Data
    }

    public override func stringArray(forKey defaultName: String) -> [String]? {
        object(forKey: defaultName) as? [String]
    }

    public override func url(forKey defaultName: String) -> URL? {
        let value = object(forKey: defaultName)
        if let url = value as? URL { return url }
        return (value as? String).map { URL(fileURLWithPath: $0) }
    }

    public override func dictionaryRepresentation() -> [String: Any] {
        lock.withLock { values }
    }
}
