//
//  Parser.swift
//  Parser
//
//  Created by Kristofer Hanes on 2018-02-10.
//  Copyright © 2018 Kristofer Hanes. All rights reserved.
//

import PreludeOSX

struct Parser<Parsed> {
  private let parse: (Stream) throws -> (parsed: Parsed, remaining: Stream)
}

extension Parser {
  
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
      do {
        while true {
          let (parsed, remaining) = try self.parsing(stream)
          result.append(parsed)
          stream = remaining
        }
      }
      catch {
        return (result, stream)
      }
    }
  }
  
  var some: Parser<[Parsed]> {
    return curried(+) <^> map { [$0] } <*> many
  }
  
}

extension Parser { // Functor
  
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

extension Parser { // Applicative
  
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
  
}

extension Parser { // Monad
  
  func flatMap<Mapped>(_ transform: @escaping (Parsed) -> Parser<Mapped>) -> Parser<Mapped> {
    return Parser<Mapped> { stream in
      let (parsed, remaining) = try self.parsing(stream)
      let newParser = transform(parsed)
      return try newParser.parsing(remaining)
    }
  }
  
}

extension Parser where Parsed == Character {
  
  static var character: Parser {
    return Parser { stream in
      guard let first = stream.input.first else {
        throw Error.endOfString
      }
      let remaining = Stream(position: stream.position + 1, input: stream.input.dropFirst())
      return (first, remaining)
    }
  }
  
  static func satifying(predicate: @escaping (Character) -> Bool) -> Parser {
    return Parser { stream in
      let (character, remaining) = try Parser.character.parsing(stream)
      guard predicate(character) else {
        throw Error.failedPredicate(position: stream.position)
      }
      return (character, remaining)
    }
  }
  
  static let lowercase = satifying { "a" <= $0 && $0 <= "z" }
  static let uppercase = satifying { "A" <= $0 && $0 <= "Z" }
  static let letter = lowercase ?? uppercase
  static let digit = satifying { "0" <= $0 && $0 <= "9" }
  static let alphaNumeric = letter ?? digit
}

enum ParserError: Error {
  case endOfString
  case failedPredicate(position: Int)
}

extension Parser {
  typealias Error = ParserError
}

struct ParserStream {
  var position: Int
  var input: Substring
}

extension Parser {
  typealias Stream = ParserStream
}

extension String {
  
  func parsed<Parsed>(with parser: Parser<Parsed>) throws -> Parsed {
    return try parser.parsing(self).parsed
  }
  
}
