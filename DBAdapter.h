#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

typedef enum {
    DBBooleanValue,
    DBIntegerValue,
    DBDecimalValue,
    DBStringValue,
    DBDateValue,
    DBDateTimeValue,
    DBBlobValue,
    DBEnumValue,
    DBSetValue,
    DBGeometryValue,
    DBGeographicValue,
    DBJSONValue,
    DBXMLValue,
    DBURLValue,
    DBIPAddressValue,
} DBValueType;

typedef enum {
    DBSourceListIconDatabase,
    DBSourceListIconTable,
    DBSourceListIconBucket,
    DBSourceListIconGear,
    DBSourceListIconView,
} DBSourceListIconType;

@protocol DBConnection;
@protocol DBDatabase;
@protocol DBDataSource;
@protocol DBResultSet;
@protocol DBRecord;

#pragma mark -

@protocol DBAdapter <NSObject>

+ (NSString *)localizedName;
+ (NSString *)primaryURLScheme;
+ (BOOL)canConnectToURL:(NSURL *)url;
+ (void)connectToURL:(NSURL *)url
             success:(void (^)(id <DBConnection> connection))success
             failure:(void (^)(NSError *error))failure;

@end

#pragma mark -

@protocol DBConnection <NSObject>

@property (readonly) NSURL *url;
@property (readonly) id <DBDatabase> database;

- (id)initWithURL:(NSURL *)url;

- (BOOL)open:(NSError **)error;
- (BOOL)close:(NSError **)error;
- (BOOL)reset:(NSError **)error;

@optional

@property (readonly) NSArray *availableDatabases;
+ (id <DBConnection>)connectionBySelectingDatabase:(id <DBDatabase>)database;

@end

#pragma mark -

@protocol DBDatabase <NSObject>

@property (readonly) id <DBConnection> connection;
@property (readonly) NSString *name;

- (NSUInteger)numberOfDataSourceGroups;
- (NSString *)dataSourceGroupAtIndex:(NSUInteger)index;

- (NSUInteger)numberOfDataSourcesInGroup:(NSString *)group;
- (id <DBDataSource>)dataSourceInGroup:(NSString *)group atIndex:(NSUInteger)index;

@optional

@property (readonly) NSDictionary *metadata;

@end

#pragma mark -

@protocol DBDataSource <NSObject>

@property (readonly) id <DBDatabase> database;

@property (readonly) NSString *name;
@property (readonly) NSUInteger numberOfRecords;

@optional

@property (readonly) NSDictionary *metadata;

- (DBSourceListIconType)sourceListIconType;

@end

@protocol DBExplorableDataSource <NSObject>

- (void)fetchResultSetForRecordsAtIndexes:(NSIndexSet *)indexes
                                  success:(void (^)(id <DBResultSet> resultSet))success
                                  failure:(void (^)(NSError *error))failure;

@end

@protocol DBQueryableDataSource <NSObject>

- (void)fetchResultSetForQuery:(NSString *)query
                       success:(void (^)(id <DBResultSet> resultSet, NSTimeInterval elapsedTime))success
                       failure:(void (^)(NSError *error))failure;

@optional

+ (NSString *)queryLanguage;

- (NSString *)queryPlanForQuery:(NSString *)query
                          error:(NSError **)error;

@end

@protocol DBVisualizableDataSource <NSObject>

- (void)fetchResultSetForDimension:(NSExpression *)dimension
                          measures:(NSArray *)measures
                           success:(void (^)(id <DBResultSet> resultSet))success
                           failure:(void (^)(NSError *error))failure;

@end

#pragma mark -

@protocol DBResultSet <NSObject>

@property (readonly) id <DBDataSource> dataSource;

- (NSUInteger)numberOfRecords;
- (NSArray *)recordsAtIndexes:(NSIndexSet *)indexes;

- (NSUInteger)numberOfFields;
- (NSString *)identifierForTableColumnAtIndex:(NSUInteger)index;

@optional

- (DBValueType)valueTypeForTableColumnAtIndex:(NSUInteger)index;
- (NSCell *)dataCellForTableColumnAtIndex:(NSUInteger)index;
- (NSSortDescriptor *)sortDescriptorPrototypeForTableColumnAtIndex:(NSUInteger)index;
@end

@protocol DBRecord <NSObject>

- (id)valueForKey:(NSString *)key;

@optional

@property (readonly) NSArray *children;

@end
