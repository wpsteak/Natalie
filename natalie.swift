#!/usr/bin/env xcrun -sdk macosx swift

//
// Natalie - Storyboard Generator Script
//
// Generate swift file based on storyboard files
//
// Usage:
// natalie.swift Main.storyboard > Storyboards.swift
// natalie.swift path/toproject/with/storyboards > Storyboards.swift
//
// Licence: MIT
// Author: Marcin Krzyżanowski http://blog.krzyzanowskim.com
//

//
//  SWXMLHash.swift
//
//  Copyright (c) 2014 David Mohundro
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation

let rootElementName = "SWXMLHash_Root_Element"

/// Simple XML parser.
public class SWXMLHash {
    /**
    Method to parse XML passed in as a string.

    :param: xml The XML to be parsed

    :returns: An XMLIndexer instance that is used to look up elements in the XML
    */
    class public func parse(xml: String) -> XMLIndexer {
        return parse((xml as NSString).dataUsingEncoding(NSUTF8StringEncoding)!)
    }

    /**
    Method to parse XML passed in as an NSData instance.

    :param: xml The XML to be parsed

    :returns: An XMLIndexer instance that is used to look up elements in the XML
    */
    class public func parse(data: NSData) -> XMLIndexer {
        var parser = XMLParser()
        return parser.parse(data)
    }

    class public func lazy(xml: String) -> XMLIndexer {
        return lazy((xml as NSString).dataUsingEncoding(NSUTF8StringEncoding)!)
    }

    class public func lazy(data: NSData) -> XMLIndexer {
        var parser = LazyXMLParser()
        return parser.parse(data)
    }
}

struct Stack<T> {
    var items = [T]()
    mutating func push(item: T) {
        items.append(item)
    }
    mutating func pop() -> T {
        return items.removeLast()
    }
    mutating func removeAll() {
        items.removeAll(keepCapacity: false)
    }
    func top() -> T {
        return items[items.count - 1]
    }
}

class LazyXMLParser : NSObject, NSXMLParserDelegate {
    override init() {
        super.init()
    }

    var root = XMLElement(name: rootElementName)
    var parentStack = Stack<XMLElement>()
    var elementStack = Stack<String>()

    var data: NSData?
    var ops: [IndexOp] = []

    func parse(data: NSData) -> XMLIndexer {
        self.data = data
        return XMLIndexer(self)
    }

    func startParsing(ops: [IndexOp]) {
        // clear any prior runs of parse... expected that this won't be necessary, but you never know
        parentStack.removeAll()
        root = XMLElement(name: rootElementName)
        parentStack.push(root)

        self.ops = ops
        let parser = NSXMLParser(data: data!)
        parser.delegate = self
        parser.parse()
    }

    func parser(parser: NSXMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [NSObject : AnyObject]) {

        elementStack.push(elementName)

        if !onMatch() {
            return
        }
        let currentNode = parentStack.top().addElement(elementName, withAttributes: attributeDict)
        parentStack.push(currentNode)
    }

    func parser(parser: NSXMLParser, foundCharacters string: String?) {
        if !onMatch() {
            return
        }

        let current = parentStack.top()
        if current.text == nil {
            current.text = ""
        }

        parentStack.top().text! += string!
    }

    func parser(parser: NSXMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let match = onMatch()

        elementStack.pop()

        if match {
            parentStack.pop()
        }
    }

    func onMatch() -> Bool {
        // we typically want to compare against the elementStack to see if it matches ops, *but*
        // if we're on the first element, we'll instead compare the other direction.
        if elementStack.items.count > ops.count {
            return startsWith(elementStack.items, ops.map { $0.key })
        }
        else {
            return startsWith(ops.map { $0.key }, elementStack.items)
        }
    }
}

/// The implementation of NSXMLParserDelegate and where the parsing actually happens.
class XMLParser : NSObject, NSXMLParserDelegate {
    override init() {
        super.init()
    }

    var root = XMLElement(name: rootElementName)
    var parentStack = Stack<XMLElement>()

    func parse(data: NSData) -> XMLIndexer {
        // clear any prior runs of parse... expected that this won't be necessary, but you never know
        parentStack.removeAll()

        parentStack.push(root)

        let parser = NSXMLParser(data: data)
        parser.delegate = self
        parser.parse()

        return XMLIndexer(root)
    }

    func parser(parser: NSXMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [NSObject : AnyObject]) {

        let currentNode = parentStack.top().addElement(elementName, withAttributes: attributeDict)
        parentStack.push(currentNode)
    }

    func parser(parser: NSXMLParser, foundCharacters string: String?) {
        let current = parentStack.top()
        if current.text == nil {
            current.text = ""
        }

        parentStack.top().text! += string!
    }

    func parser(parser: NSXMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        parentStack.pop()
    }
}

public class IndexOp {
    var index: Int
    let key: String

    init(_ key: String) {
        self.key = key
        self.index = -1
    }

    func toString() -> String {
        if index >= 0 {
            return key + " " + index.description
        }

        return key
    }
}

public class IndexOps {
    var ops: [IndexOp] = []

    let parser: LazyXMLParser

    init(parser: LazyXMLParser) {
        self.parser = parser
    }

    func findElements() -> XMLIndexer {
        parser.startParsing(ops)
        let indexer = XMLIndexer(parser.root)
        var childIndex = indexer
        for op in ops {
            childIndex = childIndex[op.key]
            if op.index >= 0 {
                childIndex = childIndex[op.index]
            }
        }
        ops.removeAll(keepCapacity: false)
        return childIndex
    }

    func stringify() -> String {
        var s = ""
        for op in ops {
            s += "[" + op.toString() + "]"
        }
        return s
    }
}

/// Returned from SWXMLHash, allows easy element lookup into XML data.
public enum XMLIndexer : SequenceType {
    case Element(XMLElement)
    case List([XMLElement])
    case Stream(IndexOps)
    case Error(NSError)

    /// The underlying XMLElement at the currently indexed level of XML.
    public var element: XMLElement? {
        get {
            switch self {
            case .Element(let elem):
                return elem
            case .Stream(let ops):
                let list = ops.findElements()
                return list.element
            default:
                return nil
            }
        }
    }

    /// All elements at the currently indexed level
    public var all: [XMLIndexer] {
        get {
            switch self {
            case .List(let list):
                var xmlList = [XMLIndexer]()
                for elem in list {
                    xmlList.append(XMLIndexer(elem))
                }
                return xmlList
            case .Element(let elem):
                return [XMLIndexer(elem)]
            case .Stream(let ops):
                let list = ops.findElements()
                return list.all
            default:
                return []
            }
        }
    }

    /// All child elements from the currently indexed level
    public var children: [XMLIndexer] {
        get {
            var list = [XMLIndexer]()
            for elem in all.map({ $0.element! }) {
                for elem in elem.children {
                    list.append(XMLIndexer(elem))
                }
            }
            return list
        }
    }

    /**
    Allows for element lookup by matching attribute values.

    :param: attr should the name of the attribute to match on
    :param: _ should be the value of the attribute to match on

    :returns: instance of XMLIndexer
    */
    public func withAttr(attr: String, _ value: String) -> XMLIndexer {
        let attrUserInfo = [NSLocalizedDescriptionKey: "XML Attribute Error: Missing attribute [\"\(attr)\"]"]
        let valueUserInfo = [NSLocalizedDescriptionKey: "XML Attribute Error: Missing attribute [\"\(attr)\"] with value [\"\(value)\"]"]
        switch self {
        case .Stream(let opStream):
            opStream.stringify()
            let match = opStream.findElements()
            return match.withAttr(attr, value)
        case .List(let list):
            if let elem = list.filter({$0.attributes[attr] == value}).first {
                return .Element(elem)
            }
            return .Error(NSError(domain: "SWXMLDomain", code: 1000, userInfo: valueUserInfo))
        case .Element(let elem):
            if let attr = elem.attributes[attr] {
                if attr == value {
                    return .Element(elem)
                }
                return .Error(NSError(domain: "SWXMLDomain", code: 1000, userInfo: valueUserInfo))
            }
            return .Error(NSError(domain: "SWXMLDomain", code: 1000, userInfo: attrUserInfo))
        default:
            return .Error(NSError(domain: "SWXMLDomain", code: 1000, userInfo: attrUserInfo))
        }
    }

    /**
    Initializes the XMLIndexer

    :param: _ should be an instance of XMLElement, but supports other values for error handling

    :returns: instance of XMLIndexer
    */
    public init(_ rawObject: AnyObject) {
        switch rawObject {
        case let value as XMLElement:
            self = .Element(value)
        case let value as LazyXMLParser:
            self = .Stream(IndexOps(parser: value))
        default:
            self = .Error(NSError(domain: "SWXMLDomain", code: 1000, userInfo: nil))
        }
    }

    /**
    Find an XML element at the current level by element name

    :param: key The element name to index by

    :returns: instance of XMLIndexer to match the element (or elements) found by key
    */
    public subscript(key: String) -> XMLIndexer {
        get {
            let userInfo = [NSLocalizedDescriptionKey: "XML Element Error: Incorrect key [\"\(key)\"]"]
            switch self {
            case .Stream(let opStream):
                let op = IndexOp(key)
                opStream.ops.append(op)
                return .Stream(opStream)
            case .Element(let elem):
                let match = elem.children.filter({ $0.name == key })
                if match.count > 0 {
                    if match.count == 1 {
                        return .Element(match[0])
                    }
                    else {
                        return .List(match)
                    }
                }
                return .Error(NSError(domain: "SWXMLDomain", code: 1000, userInfo: userInfo))
            default:
                return .Error(NSError(domain: "SWXMLDomain", code: 1000, userInfo: userInfo))
            }
        }
    }

    /**
    Find an XML element by index within a list of XML Elements at the current level

    :param: index The 0-based index to index by

    :returns: instance of XMLIndexer to match the element (or elements) found by key
    */
    public subscript(index: Int) -> XMLIndexer {
        get {
            let userInfo = [NSLocalizedDescriptionKey: "XML Element Error: Incorrect index [\"\(index)\"]"]
            switch self {
            case .Stream(let opStream):
                opStream.ops[opStream.ops.count - 1].index = index
                return .Stream(opStream)
            case .List(let list):
                if index <= list.count {
                    return .Element(list[index])
                }
                return .Error(NSError(domain: "SWXMLDomain", code: 1000, userInfo: userInfo))
            case .Element(let elem):
                if index == 0 {
                    return .Element(elem)
                }
                else {
                    return .Error(NSError(domain: "SWXMLDomain", code: 1000, userInfo: userInfo))
                }
            default:
                return .Error(NSError(domain: "SWXMLDomain", code: 1000, userInfo: userInfo))
            }
        }
    }

    typealias GeneratorType = XMLIndexer

    public func generate() -> IndexingGenerator<[XMLIndexer]> {
        return all.generate()
    }
}

/// XMLIndexer extensions
extension XMLIndexer: BooleanType {
    /// True if a valid XMLIndexer, false if an error type
    public var boolValue: Bool {
        get {
            switch self {
            case .Error:
                return false
            default:
                return true
            }
        }
    }
}

extension XMLIndexer: Printable {
    public var description: String {
        get {
            switch self {
            case .List(let list):
                return "\n".join(list.map { $0.description })
            case .Element(let elem):
                if elem.name == rootElementName {
                    return "\n".join(elem.children.map { $0.description })
                }

                return elem.description
            default:
                return ""
            }
        }
    }
}

/// Models an XML element, including name, text and attributes
public class XMLElement {
    /// The name of the element
    public let name: String
    /// The inner text of the element, if it exists
    public var text: String?
    /// The attributes of the element
    public var attributes = [String:String]()

    var children = [XMLElement]()
    var count: Int = 0
    var index: Int

    /**
    Initialize an XMLElement instance

    :param: name The name of the element to be initialized

    :returns: a new instance of XMLElement
    */
    init(name: String, index: Int = 0) {
        self.name = name
        self.index = index
    }

    /**
    Adds a new XMLElement underneath this instance of XMLElement

    :param: name The name of the new element to be added
    :param: withAttributes The attributes dictionary for the element being added

    :returns: The XMLElement that has now been added
    */
    func addElement(name: String, withAttributes attributes: NSDictionary) -> XMLElement {
        let element = XMLElement(name: name, index: count)
        count++

        children.append(element)

        for (keyAny,valueAny) in attributes {
            let key = keyAny as! String
            let value = valueAny as! String
            element.attributes[key] = value
        }

        return element
    }
}

extension XMLElement: Printable {
    public var description:String {
        get {
            var attributesStringList = [String]()
            if !attributes.isEmpty {
                for (key, val) in attributes {
                    attributesStringList.append("\(key)=\"\(val)\"")
                }
            }

            var attributesString = " ".join(attributesStringList)
            if (!attributesString.isEmpty) {
                attributesString = " " + attributesString
            }

            if children.count > 0 {
                var xmlReturn = [String]()
                xmlReturn.append("<\(name)\(attributesString)>")
                for child in children {
                    xmlReturn.append(child.description)
                }
                xmlReturn.append("</\(name)>")
                return "\n".join(xmlReturn)
            }

            if text != nil {
                return "<\(name)\(attributesString)>\(text!)</\(name)>"
            }
            else {
                return "<\(name)\(attributesString)/>"
            }
        }
    }
}


enum OS: String, Printable{
    case iOS = "iOS"
    case OSX = "OSX"
    
    static func fromString(string: String) -> OS? {
        for os in OS.allValues {
            if  NSString(string: os.rawValue).caseInsensitiveCompare(string) == NSComparisonResult.OrderedSame {
                return os
            }
        }
        return nil
    }
    
    static func fromTargetRuntime(targetRuntime: String) -> OS? {
        for os in OS.allValues {
            if  os.targetRuntime == targetRuntime {
                return os
            }
        }
        return nil
    }
    
    static let allValues = [iOS, OSX]
    
    var description: String {return self.rawValue}
    
    var framework: String {
        switch self {
        case iOS: return "UIKit"
        case OSX: return "Cocoa"
        }
    }
    
    var targetRuntime: String {
        switch self {
        case iOS: return "iOS.CocoaTouch"
        case OSX: return "MacOSX.Cocoa"
        }
    }
    
    var storyboardType: String {
        switch self {
        case iOS: return "UIStoryboard"
        case OSX: return "NSStoryboard"
        }
    }
    
    var storyboardTypeUnwrap: String {
        switch self {
        case iOS: return ""
        case OSX: return "!"
        }
    }
    
    var storyboardControllerTypes: [String] {
        switch self {
        case iOS: return ["UIViewController"]
        case OSX: return ["NSViewController", "NSWindowController"]
        }
    }
    
    var storyboardControllerSignatureType: String {
        switch self {
        case iOS: return "ViewController"
        case OSX: return "Controller" // NSViewController or NSWindowController
        }
    }
    
    var storyboardControllerReturnType: String {
        switch self {
        case iOS: return "UIViewController"
        case OSX: return "AnyObject" // NSViewController or NSWindowController
        }
    }
    
    var storyboardControllerInitialReturnTypeCast: String {
        switch self {
        case iOS: return "as? \(self.storyboardControllerReturnType)"
        case OSX: return ""
        }
    }
    
    var storyboardControllerReturnTypeCast: String {
        switch self {
        case iOS: return "as! \(self.storyboardControllerReturnType)"
        case OSX: return "!"
        }
    }
    
    func storyboardControllerInitialReturnTypeCast(initialClass: String) -> String {
        switch self {
        case iOS: return "as! \(initialClass)"
        case OSX: return ""
        }
    }
    
    var storyboardSegueType: String {
        switch self {
        case iOS: return "UIStoryboardSegue"
        case OSX: return "NSStoryboardSegue"
        }
    }
    
    var navigationControllerType: String {
        switch self {
        case iOS: return "UINavigationController"
        case OSX: return ""
        }
    }
    
    var tableViewControllerType: String {
        switch self {
        case iOS: return "UITableViewController"
        case OSX: return "NSTableViewController"
        }
    }
}

private func searchAll(root: XMLIndexer, attributeKey: String, attributeValue: String) -> [XMLIndexer]? {
    var result = Array<XMLIndexer>()
    for child in root.children {
        if let element = child.element where element.attributes[attributeKey] == attributeValue {
            return [child]
        }
        if let found = searchAll(child, attributeKey, attributeValue) {
            result += found
        }
    }
    return result.count > 0 ? result : nil
}

func findStoryboards(rootPath: String) -> [String]? {
    var result = Array<String>()
    let fm = NSFileManager.defaultManager()
    var error:NSError?
    if let paths = fm.subpathsAtPath(rootPath) as? [String]  {
        let storyboardPaths = paths.filter({ return $0.hasSuffix(".storyboard")})
        // result = storyboardPaths
        for p in storyboardPaths {
            result.append(rootPath.stringByAppendingPathComponent(p))
        }
    }
    return result.count > 0 ? result : nil
}

func findInitialViewControllerClass(storyboardFile: String, os: OS) -> String? {
    if let data = NSData(contentsOfFile: storyboardFile) {
        let xml = SWXMLHash.parse(data)
        if let initialViewControllerId = xml["document"].element?.attributes["initialViewController"] {
            if let vc = searchAll(xml["document"], "id",initialViewControllerId)?.first {
                if let customClassName = vc.element?.attributes["customClass"] {
                    return customClassName
                }

                switch (vc.element!.name) {
                    case "navigationController":
                        return "\(os.navigationControllerType)"
                    case "tableViewController":
                        return "\(os.tableViewControllerType)"
                    case "tableViewController":
                        return "\(os.tableViewControllerType)"
                    default:
                        break
                }
            }
        }
    }
    return nil
}

func findStoryboardOS(storyboardFile: String) -> OS? {
    if let data = NSData(contentsOfFile: storyboardFile) {
        let xml = SWXMLHash.parse(data)
        if let targetRuntime = xml["document"].element?.attributes["targetRuntime"] {
            return OS.fromTargetRuntime(targetRuntime)
        }
    }
    return nil
}

private func storyboardIdentifierExtenstion(viewController: XMLIndexer) -> String? {
    var result:String? = nil
    if let customClass = viewController.element?.attributes["customClass"] {
        var output = String()
        output += "extension \(customClass) {\n"
        if let viewControllerId = viewController.element?.attributes["storyboardIdentifier"] {
            output += "    override class var storyboardIdentifier:String? { return \"\(viewControllerId)\" }\n"
        }
        output += "}"
        result = output
    }
    return result
}

func processStoryboard(storyboardFile: String, os: OS) {
    if let data = NSData(contentsOfFile: storyboardFile) {
        let xml = SWXMLHash.parse(data)

        if let viewControllers = searchAll(xml, "sceneMemberID", "viewController") {
            for viewController in viewControllers {
                if let customClass = viewController.element?.attributes["customClass"] {
                    let segues = viewController["connections"]["segue"].all.filter({ return $0.element?.attributes["identifier"] != nil })

                    if segues.count > 0 {
                        println("extension \(os.storyboardSegueType) {")
                        println("    func selection() -> \(customClass).Segue? {")
                        println("        if let identifier = self.identifier {")
                        println("            return \(customClass).Segue(rawValue: identifier)")
                        println("        }")
                        println("        return nil")
                        println("    }")
                        println("}")
                    }

                    println()
                    println("//MARK: - \(customClass)")
                    if let identifierExtenstionString = storyboardIdentifierExtenstion(viewController) {
                        println()
                        println(identifierExtenstionString)
                        println()
                    }

                    if segues.count > 0 {
                        println("extension \(customClass) { ")
                        println()
                        println("    enum Segue: String, Printable, SegueProtocol {")
                        for segue in segues {
                            if let identifier = segue.element?.attributes["identifier"]
                            {
                                println("        case \(identifier) = \"\(identifier)\"")
                            }
                        }
                        println()
                        println("        var kind: SegueKind? {")
                        println("            switch (self) {")
                        for segue in segues {
                            if let identifier = segue.element?.attributes["identifier"],
                               let kind = segue.element?.attributes["kind"] {
                                println("            case \(identifier):")
                                println("                return SegueKind(rawValue: \"\(kind)\")")
                            }
                        }
                        println("            default:")
                        println("                preconditionFailure(\"Invalid value\")")
                        println("                break")
                        println("            }")
                        println("        }")
                        println()
                        println("        var destination: UIViewController.Type? {")
                        println("            switch (self) {")
                        for segue in segues {
                            if let identifier = segue.element?.attributes["identifier"],
                               let destination = segue.element?.attributes["destination"],
                               let destinationCustomClass = searchAll(xml, "id", destination)?.first?.element?.attributes["customClass"] {

                                // let dstCustomClass = destinationViewController.element!.attributes["customClass"]
                                println("            case \(identifier):")
                                println("                return \(destinationCustomClass).self")                                
                            }
                        }
                        println("            default:")
                        println("                assertionFailure(\"Unknown destination\")")                                
                        println("                return nil")        
                        println("            }")
                        println("        }")
                        println()
                        println("        var identifier: String { return self.description } ")
                        println("        var description: String { return self.rawValue }")
                        println("    }")
                        println()
                        println("}\n")
                    }
                }
            }
        }
    }
}

func processStoryboards(storyboards: [String], os: OS) {
    println("//")
    println("// Autogenerated by Natalie - Storyboard Generator Script.")
    println("// http://blog.krzyzanowskim.com")
    println("//")
    println()
    println("import \(os.framework)")
    println()
    println("//MARK: - Storyboards")
    println("enum Storyboards: String {")
    for storyboard in storyboards {
        let storyboardName = storyboard.lastPathComponent.stringByDeletingPathExtension
        println("    case \(storyboardName) = \"\(storyboardName)\"")
    }
    println()
    println("    private var instance:\(os.storyboardType) {")
    println("        return \(os.storyboardType)(name: self.rawValue, bundle: nil)\(os.storyboardTypeUnwrap)")
    println("    }")
    println()
    println("    func instantiateInitial\(os.storyboardControllerSignatureType)() -> \(os.storyboardControllerReturnType)? {")
    println("        switch (self) {")
    for storyboard in storyboards {
        let storyboardName = storyboard.lastPathComponent.stringByDeletingPathExtension
        if let initialViewControllerClass = findInitialViewControllerClass(storyboard, os) {
            println("        case \(storyboardName):")
            println("            return self.instance.instantiateInitial\(os.storyboardControllerSignatureType)() \(os.storyboardControllerInitialReturnTypeCast(initialViewControllerClass))")

        }
    }
    println("        default:")
    println("            return self.instance.instantiateInitial\(os.storyboardControllerSignatureType)() \(os.storyboardControllerInitialReturnTypeCast)")
    println("        }")
    println("    }")
    println()
    println("    func instantiate\(os.storyboardControllerSignatureType)WithIdentifier(identifier: String) -> \(os.storyboardControllerReturnType) {")
    println("        return self.instance.instantiate\(os.storyboardControllerSignatureType)WithIdentifier(identifier) \(os.storyboardControllerReturnTypeCast)")
    println("    }")
    println("}")
    println()
    
    println("//MARK: - SegueKind")
    println("enum SegueKind: String, Printable {    ")
    println("    case Relationship = \"relationship\" ")
    println("    case Show = \"show\"                 ")
    println("    case Presentation = \"presentation\" ")
    println("    case Embed = \"embed\"               ")
    println("    case Unwind = \"unwind\"             ")
    println()
    println("    var description: String { return self.rawValue } ")
    println("}")
    println()
    
    println("//MARK: - SegueProtocol")
    println("protocol SegueProtocol {")
    println("    var identifier: String { get }")
    println("}")
    println()
    
    for controllerType in os.storyboardControllerTypes {
        println("//MARK: - \(controllerType) extension")
        println("extension \(controllerType) {")
        println("    class var storyboardIdentifier:String? { return nil }")
        println("    func performSegue(segue: SegueProtocol, sender: AnyObject?) {")
        println("       performSegueWithIdentifier(segue.identifier, sender: sender)")
        println("    }")
        println("}")
        println()
    }
    
    for storyboardPath in storyboards {
        processStoryboard(storyboardPath, os)
    }

}

//MARK: MAIN()

if Process.arguments.count == 1 {
    println("Invalid usage. Missing path to storyboard.")
    exit(0)
}

let argument = Process.arguments[1]
var storyboards:[String] = []
if argument.hasSuffix(".storyboard") {
    storyboards = [argument]
} else if let s = findStoryboards(argument) {
    storyboards = s
}

for os in OS.allValues {
    var storyboardsForOS = storyboards.filter { findStoryboardOS($0) ?? OS.iOS == os }
    if !storyboardsForOS.isEmpty {
        processStoryboards(storyboardsForOS, os)
    }
}
