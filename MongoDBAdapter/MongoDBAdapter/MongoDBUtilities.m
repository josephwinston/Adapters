// MongoDBUtilities.m
//
// Copyright (c) 2012 Mattt Thompson (http://mattt.me)
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "MongoDBUtilities.h"

static int const kMongoDBBufferSize = (24 * 2 + 1); // 24 hex chars + 1 NUL

NSDictionary * NSDictionaryFromBSON(bson *bson) {
    bson_iterator iterator;
    bson_iterator_init(&iterator, bson->data);
    
    return NSDictionaryFromBSONIterator(&iterator);
}

NSObject * NSObjectFromBSONIterator(bson_iterator *iterator) {
    switch(bson_iterator_type(iterator)) {
        case bson_bool:   return [NSNumber numberWithInt:bson_iterator_bool(iterator)];
        case bson_int:    return [NSNumber numberWithInt:bson_iterator_int(iterator)];
        case bson_long:   return [NSNumber numberWithLong:bson_iterator_long(iterator)];
        case bson_double: return [NSNumber numberWithDouble:bson_iterator_double(iterator)];
        case bson_string: return [NSString stringWithCString:bson_iterator_string(iterator) encoding:NSUTF8StringEncoding];
        case bson_null:   return [NSNull null];
            
        case bson_oid: {
            char *buffer = (char *)malloc(kMongoDBBufferSize);
            if (buffer) {
                bson_oid_to_string(bson_iterator_oid(iterator), buffer);
                NSString *oid = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
                free(buffer);
                
                return oid;
            } else {
                return @"OID: Out of memory";
            }
        } 
            
        case bson_array: {
            bson_iterator subiterator;
            bson_iterator_subiterator(iterator, &subiterator);
            return NSArrayFromBSONIterator(&subiterator);
        }
            
        case bson_object: {
            bson_iterator subiterator;
            bson_iterator_subiterator(iterator, &subiterator);
            return NSDictionaryFromBSONIterator(&subiterator);
        }
            
        case bson_date:
        case bson_timestamp:
            return [NSDate dateWithTimeIntervalSince1970:bson_iterator_date(iterator) / 1000L];
        default:
            NSLog(@"Unhandled type %d", bson_iterator_type(iterator));
            
            return [NSNull null];
    }
}

NSArray * NSArrayFromBSONIterator(bson_iterator *iterator) {
    NSMutableArray *mutableArray = [NSMutableArray array];
    while (bson_iterator_next(iterator)) {
        [mutableArray addObject:NSObjectFromBSONIterator(iterator)];
    }
    
    return [NSArray arrayWithArray:mutableArray];
}

NSDictionary * NSDictionaryFromBSONIterator(bson_iterator *iterator) {
    NSMutableDictionary *mutableDictionary = [NSMutableDictionary dictionary];
    while(bson_iterator_next(iterator)) {
        const char *key = bson_iterator_key(iterator);
        [mutableDictionary setObject:NSObjectFromBSONIterator(iterator) forKey:[NSString stringWithUTF8String:key]];
    }
    
    return [NSDictionary dictionaryWithDictionary:mutableDictionary];
}

extern void BSONBufferFillFromDictionary(bson_buffer *buffer, NSDictionary *dictionary) {
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        NSLog(@"%@: %@", key, object);
        
        if ([object isKindOfClass:[NSNumber class]]) {
            bson_append_double(buffer, [key UTF8String], [object doubleValue]);
        } else if ([object isKindOfClass:[NSString class]]) {
            bson_append_string(buffer, [key UTF8String], [object UTF8String]);
        } else if ([object isKindOfClass:[NSDate class]]) {
            bson_append_time_t(buffer, [key UTF8String], [object timeIntervalSince1970]);
        } else if ([object isKindOfClass:[NSNull class]]) {
            bson_append_null(buffer, [key UTF8String]);
        } else if ([object isKindOfClass:[NSArray class]]) {
            // TODO
        } else if ([object isKindOfClass:[NSDictionary class]]) {
            bson_append_start_object(buffer, [key UTF8String]);
            BSONBufferFillFromDictionary(buffer, object);
            bson_append_finish_object(buffer);
        } else {
            NSLog(@"Unexpected class: %@", [object class]);
        }
    }];
}

