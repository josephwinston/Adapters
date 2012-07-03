// MongoDBAdapter.m
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

#import "MongoDBAdapter.h"
#import "MongoDBUtilities.h"

static dispatch_queue_t induction_mongo_adapter_queue() {
    static dispatch_queue_t _induction_mongo_adapter_queue;
    if (_induction_mongo_adapter_queue == NULL) {
        _induction_mongo_adapter_queue = dispatch_queue_create("com.induction.mongo.adapter.queue", DISPATCH_QUEUE_SERIAL);
    }
    
    return _induction_mongo_adapter_queue;
}

@implementation MongoDBAdapter

+ (NSString *)localizedName {
    return NSLocalizedString(@"MongoDB", nil);
}

+ (NSString *)primaryURLScheme {
    return @"mongodb";
}

+ (BOOL)canConnectToURL:(NSURL *)url {
    return [[url scheme] isEqualToString:[self primaryURLScheme]] && [url host];
}

+ (void)connectToURL:(NSURL *)url
             success:(void (^)(id <DBConnection> connection))success
             failure:(void (^)(NSError *error))failure
{    
    dispatch_async(induction_mongo_adapter_queue(), ^(void) {
        MongoDBConnection *connection = [[MongoDBConnection alloc] initWithURL:url];
        NSError *error = nil;    
        BOOL connected = [connection open:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            if (connected) {
                if (success) {
                    success(connection);
                }
            } else {
                if (failure) {
                    failure(error);
                }
            }
        });
    });
}

@end

#pragma mark -

@implementation MongoDBConnection {
@public
    mongo_connection *_mongo_connection;
    MongoDBDatabase *_database;
@private
    __strong NSURL *_url;
}

@synthesize url = _url;
@synthesize database = _database;

- (id)initWithURL:(NSURL *)url {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _url = url;
    
    return self;
}

- (BOOL)open:(NSError *__autoreleasing *)error {
    [self close:nil];    
    
    mongo_connection_options options;
    strcpy(options.host, [[_url host] UTF8String]);
    if ([_url port]) {
        options.port = [[_url port] intValue];
    } else {
        options.port = 27017;
    }
    
    mongo_conn_return result;
    _mongo_connection = (mongo_connection *)malloc(sizeof(mongo_connection));
    if (_mongo_connection) {
        result = mongo_connect(_mongo_connection, &options);
        
        // TODO: Default to correct database
        _database = [[self availableDatabases] lastObject];
        
        return YES;
    } else {
        // TODO Error handling
        result = mongo_conn_fail;
        
        return NO;
    }
}

- (BOOL)close:(NSError *__autoreleasing *)error {
    if (!_mongo_connection) {
        return NO;
    }
    
    mongo_destroy(_mongo_connection);
    free(_mongo_connection);
    _mongo_connection = NULL;
    
    return YES;
}

// TODO
- (BOOL)reset:(NSError *__autoreleasing *)error {
    return NO;
}

- (id <DBResultSet>)resultSetByRunningCommand:(id)command 
                                   onDatabase:(MongoDBDatabase *)database
                                        error:(NSError **)error
{
    return nil;
}

- (void)runCommand:(id)command 
        onDatabase:(id <DBDatabase>)database
           success:(void (^)(MongoDBResultSet *resultSet, NSTimeInterval elapsedTime))success
           failure:(void (^)(NSError *error))failure
{
    return;
}

- (NSArray *)availableDatabases {
    bson queryBSON, outBSON;
    bson_buffer buffer;
    
    bson_buffer_init(&buffer);
    bson_append_int(&buffer, "listDatabases", 1);
    
    bson_bool_t result;
    result = mongo_run_command(_mongo_connection, "admin", bson_from_buffer(&queryBSON, &buffer), bson_empty(&outBSON));
    if (!result) {
        bson_destroy(&outBSON);
        bson_destroy(&queryBSON);
        bson_buffer_destroy(&buffer);
        
        return [NSArray array];
    }
    
    bson_iterator iterator;
    bson_iterator_init(&iterator, outBSON.data);
    NSDictionary *dictionary = NSDictionaryFromBSONIterator(&iterator);
    
    NSMutableArray *mutableDatabases = [NSMutableArray array];
    for (NSDictionary *attributes in [dictionary objectForKey:@"databases"]) {
        MongoDBDatabase *database = [[MongoDBDatabase alloc] initWithConnection:self attributes:attributes];
        [mutableDatabases addObject:database];
    }
    
    bson_destroy(&outBSON);
    bson_destroy(&queryBSON);
    
    return [NSArray arrayWithArray:mutableDatabases];
}

@end

#pragma mark -

@implementation MongoDBDatabase {
    __strong MongoDBConnection *_connection;
    __strong NSString *_name;
    __strong NSArray *_collections;
}

@synthesize connection = _connection;
@synthesize name = _name;

- (id)initWithConnection:(MongoDBConnection *)connection
              attributes:(NSDictionary *)attributes
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _connection = connection;
    _name = [attributes objectForKey:@"name"];
    
    NSMutableArray *mutableCollections = [NSMutableArray array];
    bson queryBSON, fieldsBSON;
    const char *namespace = [[_name stringByAppendingString:@".system.namespaces"] UTF8String];
    mongo_cursor *cursor = mongo_find(_connection->_mongo_connection, namespace, bson_empty(&queryBSON), bson_empty(&fieldsBSON), 0, 0, 0);
    while(mongo_cursor_next(cursor)) {
        bson_iterator iterator;
        bson_iterator_init(&iterator, cursor->current.data);
        
        NSDictionary *attributes = NSDictionaryFromBSONIterator(&iterator);
        if ([[attributes objectForKey:@"name"] rangeOfString:@"$"].location == NSNotFound) {
            MongoDBCollection *collection = [[MongoDBCollection alloc] initWithDatabase:self attributes:attributes];
            [mutableCollections addObject:collection];
        }
    }
    
    _collections = mutableCollections;
    
    mongo_cursor_destroy(cursor);
    
    return self;
}

- (NSDictionary *)metadata {
    return nil;
}

- (NSUInteger)numberOfDataSourceGroups {
    return 1;
}

- (NSString *)dataSourceGroupAtIndex:(NSUInteger)index {
    return NSLocalizedString(@"Collections", nil);
}

- (NSUInteger)numberOfDataSourcesInGroup:(NSString *)group {
    return [_collections count];
}

- (id <DBDataSource>)dataSourceInGroup:(NSString *)group atIndex:(NSUInteger)index {
    return [_collections objectAtIndex:index];
}

@end

#pragma mark -

@implementation MongoDBCollection {
@private
    __strong MongoDBDatabase *_database;
    __strong NSString *_name;
}

@synthesize name = _name;
@synthesize database = _database;

- (id)initWithDatabase:(MongoDBDatabase *)database
            attributes:(NSDictionary *)attributes
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _database = database;
    _name = [[[attributes objectForKey:@"name"] componentsSeparatedByString:@"."] lastObject];
    
    return self;
}

- (NSUInteger)numberOfRecords {
    bson queryBSON;
    bson_empty(&queryBSON);
    MongoDBConnection *connection = (MongoDBConnection *)_database.connection;
    
    NSUInteger count = mongo_count(connection->_mongo_connection, [_database.name UTF8String], [_name UTF8String], &queryBSON);
    
    bson_destroy(&queryBSON);
    
    return count;
}

- (NSString *)namespace {
    return [NSString stringWithFormat:@"%@.%@", _database.name, _name];
}

#pragma mark - DBExplorableDataSource

// TODO: Error Handling
- (void)fetchResultSetForRecordsAtIndexes:(NSIndexSet *)indexes 
                                  success:(void (^)(id<DBResultSet>))success 
                                  failure:(void (^)(NSError *))failure
{
    dispatch_async(induction_mongo_adapter_queue(), ^{
        bson_buffer buffer;
        bson_buffer_init(&buffer);
        BSONBufferFillFromDictionary(&buffer, [NSDictionary dictionary]);
        
        bson queryBSON;
        bson_empty(&queryBSON);
        bson_from_buffer(&queryBSON, &buffer);
        
        bson fieldsBSON;
        bson_empty(&fieldsBSON);
        
        MongoDBConnection *connection = (MongoDBConnection *)_database.connection;
        mongo_cursor *cursor;
        cursor = mongo_find(connection->_mongo_connection, [self.namespace UTF8String], &queryBSON, &fieldsBSON, (int)[indexes count], (int)[indexes firstIndex], 0);
        
        bson_destroy(&fieldsBSON);
        bson_destroy(&queryBSON);
        //    bson_buffer_destroy(&buffer);
        
        MongoDBResultSet *resultSet = [[MongoDBResultSet alloc] initWithCursor:cursor];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                success(resultSet);
            }
        });
    });        
}

// TODO
- (void)fetchResultSetForQuery:(NSString *)query 
                       success:(void (^)(id<DBResultSet>, NSTimeInterval))success 
                       failure:(void (^)(NSError *))failure 
{
    return;
}

@end

#pragma mark -

@implementation MongoDBResultSet {
@private
    __strong NSArray *_documents;
    __strong NSArray *_fields;
    mongo_cursor *_cursor;
}

- (void)dealloc {
    if (_cursor) {
        mongo_cursor_destroy(_cursor);
    }
}

- (id)initWithCursor:(void *)cursor {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _cursor = cursor;
    
    // TODO - Get cursor to respect limit of query
    //    NSMutableArray *mutableDocuments = [NSMutableArray array];
    //    while (mongo_cursor_next(cursor)) {
    //        NSDictionary *attributes = NSDictionaryFromBSON(&((mongo_cursor *)cursor)->current);
    //        MongoDBDocument *document = [[MongoDBDocument alloc] initWithDictionary:attributes];
    //        [mutableDocuments addObject:document];
    //    }
    //    
    //    _documents = mutableDocuments;
    
    _fields = [NSArray arrayWithObjects:@"key", @"value", nil];
    
    //    mongo_cursor_destroy(cursor);
    
    return self;
}

- (NSUInteger)numberOfRecords {
    return 256;
    //    return [_documents count];
}

- (NSArray *)recordsAtIndexes:(NSIndexSet *)indexes {
    //    return [_documents objectsAtIndexes:indexes];
    
    NSMutableArray *mutableDocuments = [NSMutableArray array];
    while (mongo_cursor_next(_cursor)) {
        NSDictionary *attributes = NSDictionaryFromBSON(&_cursor->current);
        MongoDBDocument *document = [[MongoDBDocument alloc] initWithDictionary:attributes];
        [mutableDocuments addObject:document];
        
        if ([mutableDocuments count] > [indexes lastIndex]) {
            break;
        }
    }
    
    return mutableDocuments;
}

- (NSUInteger)numberOfFields {
    return [_fields count];
}

- (NSString *)identifierForTableColumnAtIndex:(NSUInteger)index {
    return [_fields objectAtIndex:index];
}

@end

#pragma mark -

@interface MongoDBDocument ()
@property (nonatomic, strong, readwrite) NSString *key;
@property (nonatomic, strong, readwrite) id value;
@end

@implementation MongoDBDocument {
@private
    __strong NSString *_key;
    __strong id _value;
    __strong NSArray *_children;
}

@synthesize key = _key;
@synthesize value = _value;
@synthesize children = _children;

- (id)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _key = [dictionary objectForKey:@"_id"];
    
    NSMutableArray *mutableChildren = [NSMutableArray arrayWithCapacity:[dictionary count]];
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (![key isEqualToString:@"_id"]) {
            MongoDBDocument *document = nil;
            
            if ([value isKindOfClass:[NSDictionary class]]) {
                document = [[MongoDBDocument alloc] initWithDictionary:value];
                document.key = key;
            } else {
                document = [[MongoDBDocument alloc] init];
                document.key = key;
                document.value = value;
            }
            
            [mutableChildren addObject:document];
        }
    }];
    
    _value = @"";
    _children = mutableChildren;
    
    return self;
}

@end
