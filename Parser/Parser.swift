//
//  Parser.swift
//  Parser
//
//  Created by Kristofer Hanes on 2018-02-10.
//  Copyright © 2018 Kristofer Hanes. All rights reserved.
//

import Foundation
import PreludeOSX

public struct Parser<Parsed> {
  private let parse: (Stream) throws -> (parsed: Parsed, remaining: Stream)
}

public extension Parser {
  
  func parsing(_ input: String) throws -> (parsed: Parsed, remaining: String) {
    let (parsed, remaining) = try parse(Stream(position: 0, input: Substring(input)))
    return (parsed, String(remaining.input))
  }
  
  func parsing(_ stream: Stream) throws -> (parsed: Parsed, remaining: Stream) {
    return try parse(stream)
  }
  
  static func ?? (lhs: Parser, rhs: Parser) -> Parser {
    return Parser { stream in
      do {
        return try lhs.parsing(stream)
      }
      catch {
        return try rhs.parsing(stream)
      }
    }
  }
  
  var many: Parser<[Parsed]> {
    return Parser<[Parsed]> { stream in
      var stream = stream
      var result: [Parsed] = []
      while let (parsed, remaining) = try? self.parsing(stream) {
        result.append(parsed)
        stream = remaining
      }
      return (result, stream)
    }
  }
  
  var some: Parser<[Parsed]> {
    return curried(+) <^> map { [$0] } <*> many
  }
  
  var optional: Parser<Parsed?> {
    return Parser<Parsed?> { stream in
      do {
        let (parsed, remaining) = try self.parsing(stream)
        return (.some(parsed), remaining)
      }
      catch {
        return (.none, stream)
      }
    }
  }
  
}

public extension Parser { // Functor
  
  func map<Mapped>(_ transform: @escaping (Parsed) -> Mapped) -> Parser<Mapped> {
    return Parser<Mapped> { [parse] stream in
      let (parsed, remaining) = try parse(stream)
      let mapped = transform(parsed)
      return (mapped, remaining)
    }
  }
  
  static func <^> <Mapped>(transform: @escaping (Parsed) -> Mapped, parser: Parser) -> Parser<Mapped> {
    return parser.map(transform)
  }
  
}

public extension Parser { // Applicative
  
  static func pure(_ value: Parsed) -> Parser {
    return Parser { stream in (value, stream) }
  }
  
  static func <*> <Mapped>(transform: Parser<(Parsed) -> Mapped>, parser: Parser) -> Parser<Mapped> {
    return Parser<Mapped> { stream in
      let (fn, remaining) = try transform.parsing(stream)
      let (parsed, remaining1) = try parser.parsing(remaining)
      return (fn(parsed), remaining1)
    }
  }
  
  static func <* <Ignored>(parser: Parser, ignored: Parser<Ignored>) -> Parser {
    return fst <^> parser <*> ignored
  }
  
  static func *> <Ignored>(ignored: Parser<Ignored>, parser: Parser) -> Parser {
    return snd <^> ignored <*> parser
  }
  
}

public extension Parser { // Monad
  
  func flatMap<Mapped>(_ transform: @escaping (Parsed) -> Parser<Mapped>) -> Parser<Mapped> {
    return Parser<Mapped> { stream in
      let (parsed, remaining) = try self.parsing(stream)
      let newParser = transform(parsed)
      return try newParser.parsing(remaining)
    }
  }
  
}

public extension Parser where Parsed == Character {
  
  static var character: Parser {
    return Parser { stream in
      guard let first = stream.input.first else {
        throw Error.endOfString
      }
      let remaining = Stream(position: stream.position + 1, input: stream.input.dropFirst())
      return (first, remaining)
    }
  }
  
  static func satisfying(predicate: @escaping (Character) -> Bool) -> Parser {
    return Parser { stream in
      let (character, remaining) = try Parser.character.parsing(stream)
      guard predicate(character) else {
        throw Error.failedPredicate(position: stream.position)
      }
      return (character, remaining)
    }
  }
  
  static let lowercase = satisfying { "a" <= $0 && $0 <= "z" }
  static let uppercase = satisfying { "A" <= $0 && $0 <= "Z" }
  static let letter = lowercase ?? uppercase
  static let digit = satisfying { "0" <= $0 && $0 <= "9" }
  static let alphaNumeric = letter ?? digit
}

public extension Parser where Parsed == String {
  
  static var string: Parser {
    return Parser { stream in
      let result = String(stream.input)
      let newStream = Stream(position: stream.position + result.count, input: "")
      return (result, newStream)
    }
  }
  
  static func satisfying(predicate: @escaping (String) -> Bool) -> Parser {
    return Parser { stream in
      let (parsed, remaining) = try string.parsing(stream)
      if predicate(parsed) {
        return (parsed, remaining)
      }
      else {
        throw Error.failedPredicate(position: stream.position)
      }
    }
  }
  
  static func string(upto ending: String) -> Parser {
    return Parser { stream in
      guard let range = stream.input.range(of: ending) else {
        throw Error.endOfString
      }
      let result = String(stream.input.prefix(upTo: range.lowerBound))
      let remaining = stream.input.dropFirst(result.count)
      let position = stream.position + result.count
      return (result, Stream(position: position, input: remaining))
    }
  }
  
  static func bracket(open: String, close: String) -> Parser {
    let opener = Parser<String>.satisfying { $0 == open }
    let closer = Parser<String>.satisfying { $0 == close }
    return bracket(open: opener, close: closer)
  }
  
  static func bracket(open: Parser, close: Parser) -> Parser {
    let middle = close.flatMap { Parser.string(upto: $0) }
    return open *> middle <* close
  }
  
}

public enum ParserError: Error {
  case endOfString
  case failedPredicate(position: Int)
}

public extension Parser {
  typealias Error = ParserError
}

public struct ParserStream {
  var position: Int
  var input: Substring
}

public extension Parser {
  typealias Stream = ParserStream
}

public extension String {
  
  func parsed<Parsed>(with parser: Parser<Parsed>) throws -> Parsed {
    return try parser.parsing(self).parsed
  }
  
}
