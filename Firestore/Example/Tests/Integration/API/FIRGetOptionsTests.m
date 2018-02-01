/*
 * Copyright 2018 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

@import FirebaseFirestore;

#import <XCTest/XCTest.h>

#import "Firestore/Example/Tests/Util/FSTIntegrationTestCase.h"
#import "Firestore/Source/API/FIRFirestore+Internal.h"
#import "Firestore/Source/Core/FSTFirestoreClient.h"

@interface FIRGetOptionsTests : FSTIntegrationTestCase
@end

@implementation FIRGetOptionsTests

- (void)testGetDocumentWhileOnlineWithDefaultGetOptions {
  FIRDocumentReference *doc = [self documentRef];

  // set document to a known value
  NSDictionary<NSString *, id> *initialData = @{@"key" : @"value"};
  [self writeDocumentRef:doc data:initialData];

  // get doc and ensure that it exists, is *not* from the cache, and matches
  // the initialData.
  FIRDocumentSnapshot *result = [self readDocumentForRef:doc];
  XCTAssertTrue(result.exists);
  XCTAssertFalse(result.metadata.fromCache);
  XCTAssertFalse(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(result.data, initialData);
}

- (void)testGetCollectionWhileOnlineWithDefaultGetOptions {
  FIRCollectionReference *col = [self collectionRef];

  // set a few documents to known values
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *initialDocs = @{
    @"doc1" : @{@"key1" : @"value1"},
    @"doc2" : @{@"key2" : @"value2"},
    @"doc3" : @{@"key3" : @"value3"}
  };
  [self writeAllDocuments:initialDocs toCollection:col];

  // get docs and ensure they are *not* from the cache, and match the
  // initialDocs.
  FIRQuerySnapshot *result = [self readDocumentSetForRef:col];
  XCTAssertFalse(result.metadata.fromCache);
  XCTAssertFalse(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(
      FIRQuerySnapshotGetData(result),
      (@[ @{@"key1" : @"value1"}, @{@"key2" : @"value2"}, @{@"key3" : @"value3"} ]));
  XCTAssertEqualObjects(FIRQuerySnapshotGetDocChangesData(result), (@[
                          @[ @(FIRDocumentChangeTypeAdded), @"doc1", @{@"key1" : @"value1"} ],
                          @[ @(FIRDocumentChangeTypeAdded), @"doc2", @{@"key2" : @"value2"} ],
                          @[ @(FIRDocumentChangeTypeAdded), @"doc3", @{@"key3" : @"value3"} ]
                        ]));
}

- (void)testGetDocumentWhileOfflineWithDefaultGetOptions {
  FIRDocumentReference *doc = [self documentRef];

  // set document to a known value
  NSDictionary<NSString *, id> *initialData = @{@"key1" : @"value1"};
  [self writeDocumentRef:doc data:initialData];

  // go offline for the rest of this test
  [self disableNetwork];

  // update the doc (though don't wait for a server response. We're offline; so
  // that ain't happening!). This allows us to further distinguished cached vs
  // server responses below.
  NSDictionary<NSString *, id> *newData = @{@"key2" : @"value2"};
  [doc setData:newData
      completion:^(NSError *_Nullable error) {
        XCTAssertTrue(false, "Because we're offline, this should never occur.");
      }];

  // get doc and ensure it exists, *is* from the cache, and matches the
  // newData.
  FIRDocumentSnapshot *result = [self readDocumentForRef:doc];
  XCTAssertTrue(result.exists);
  XCTAssertTrue(result.metadata.fromCache);
  XCTAssertTrue(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(result.data, newData);
}

- (void)testGetCollectionWhileOfflineWithDefaultGetOptions {
  FIRCollectionReference *col = [self collectionRef];

  // set a few documents to known values
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *initialDocs = @{
    @"doc1" : @{@"key1" : @"value1"},
    @"doc2" : @{@"key2" : @"value2"},
    @"doc3" : @{@"key3" : @"value3"}
  };
  [self writeAllDocuments:initialDocs toCollection:col];

  // go offline for the rest of this test
  [self disableNetwork];

  // update the docs (though don't wait for a server response. We're offline; so
  // that ain't happening!). This allows us to further distinguished cached vs
  // server responses below.
  [[col documentWithPath:@"doc2"] setData:@{@"key2b" : @"value2b"} options:FIRSetOptions.merge];
  [[col documentWithPath:@"doc3"] setData:@{@"key3b" : @"value3b"}];
  [[col documentWithPath:@"doc4"] setData:@{@"key4" : @"value4"}];

  // get docs and ensure they *are* from the cache, and matches the updated data.
  FIRQuerySnapshot *result = [self readDocumentSetForRef:col];
  XCTAssertTrue(result.metadata.fromCache);
  XCTAssertTrue(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(FIRQuerySnapshotGetData(result), (@[
                          @{@"key1" : @"value1"}, @{@"key2" : @"value2", @"key2b" : @"value2b"},
                          @{@"key3b" : @"value3b"}, @{@"key4" : @"value4"}
                        ]));
  XCTAssertEqualObjects(
      FIRQuerySnapshotGetDocChangesData(result), (@[
        @[ @(FIRDocumentChangeTypeAdded), @"doc1", @{@"key1" : @"value1"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc2", @{@"key2" : @"value2", @"key2b" : @"value2b"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc3", @{@"key3b" : @"value3b"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc4", @{@"key4" : @"value4"} ]
      ]));
}

- (void)testGetDocumentWhileOnlineCacheOnly {
  FIRDocumentReference *doc = [self documentRef];

  // set document to a known value
  NSDictionary<NSString *, id> *initialData = @{@"key" : @"value"};
  [self writeDocumentRef:doc data:initialData];

  // get doc and ensure that it exists, *is* from the cache, and matches
  // the initialData.
  FIRDocumentSnapshot *result =
      [self readDocumentForRef:doc options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceCache]];
  XCTAssertTrue(result.exists);
  XCTAssertTrue(result.metadata.fromCache);
  XCTAssertFalse(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(result.data, initialData);
}

- (void)testGetCollectionWhileOnlineCacheOnly {
  FIRCollectionReference *col = [self collectionRef];

  // set a few documents to a known value
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *initialDocs = @{
    @"doc1" : @{@"key1" : @"value1"},
    @"doc2" : @{@"key2" : @"value2"},
    @"doc3" : @{@"key3" : @"value3"},
  };
  [self writeAllDocuments:initialDocs toCollection:col];

  // get docs and ensure they *are* from the cache, and matches the
  // initialDocs.
  FIRQuerySnapshot *result =
      [self readDocumentSetForRef:col options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceCache]];
  XCTAssertTrue(result.metadata.fromCache);
  XCTAssertFalse(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(FIRQuerySnapshotGetData(result), (@[
                          @{@"key1" : @"value1"},
                          @{@"key2" : @"value2"},
                          @{@"key3" : @"value3"},
                        ]));
  XCTAssertEqualObjects(FIRQuerySnapshotGetDocChangesData(result), (@[
                          @[ @(FIRDocumentChangeTypeAdded), @"doc1", @{@"key1" : @"value1"} ],
                          @[ @(FIRDocumentChangeTypeAdded), @"doc2", @{@"key2" : @"value2"} ],
                          @[ @(FIRDocumentChangeTypeAdded), @"doc3", @{@"key3" : @"value3"} ]
                        ]));
}

- (void)testGetDocumentWhileOfflineCacheOnly {
  FIRDocumentReference *doc = [self documentRef];

  // set document to a known value
  NSDictionary<NSString *, id> *initialData = @{@"key1" : @"value1"};
  [self writeDocumentRef:doc data:initialData];

  // go offline for the rest of this test
  [self disableNetwork];

  // update the doc (though don't wait for a server response. We're offline; so
  // that ain't happening!). This allows us to further distinguished cached vs
  // server responses below.
  NSDictionary<NSString *, id> *newData = @{@"key2" : @"value2"};
  [doc setData:newData
      completion:^(NSError *_Nullable error) {
        XCTFail("Because we're offline, this should never occur.");
      }];

  // get doc and ensure it exists, *is* from the cache, and matches the
  // newData.
  FIRDocumentSnapshot *result =
      [self readDocumentForRef:doc options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceCache]];
  XCTAssertTrue(result.exists);
  XCTAssertTrue(result.metadata.fromCache);
  XCTAssertTrue(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(result.data, newData);
}

- (void)testGetCollectionWhileOfflineCacheOnly {
  FIRCollectionReference *col = [self collectionRef];

  // set a few documents to a known value
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *initialDocs = @{
    @"doc1" : @{@"key1" : @"value1"},
    @"doc2" : @{@"key2" : @"value2"},
    @"doc3" : @{@"key3" : @"value3"},
  };
  [self writeAllDocuments:initialDocs toCollection:col];

  // go offline for the rest of this test
  [self disableNetwork];

  // update the docs (though don't wait for a server response. We're offline; so
  // that ain't happening!). This allows us to further distinguished cached vs
  // server responses below.
  [[col documentWithPath:@"doc2"] setData:@{@"key2b" : @"value2b"} options:FIRSetOptions.merge];
  [[col documentWithPath:@"doc3"] setData:@{@"key3b" : @"value3b"}];
  [[col documentWithPath:@"doc4"] setData:@{@"key4" : @"value4"}];

  // get docs and ensure they *are* from the cache, and matches the updated
  // data.
  FIRQuerySnapshot *result =
      [self readDocumentSetForRef:col options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceCache]];
  XCTAssertTrue(result.metadata.fromCache);
  XCTAssertTrue(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(FIRQuerySnapshotGetData(result), (@[
                          @{@"key1" : @"value1"}, @{@"key2" : @"value2", @"key2b" : @"value2b"},
                          @{@"key3b" : @"value3b"}, @{@"key4" : @"value4"}
                        ]));
  XCTAssertEqualObjects(
      FIRQuerySnapshotGetDocChangesData(result), (@[
        @[ @(FIRDocumentChangeTypeAdded), @"doc1", @{@"key1" : @"value1"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc2", @{@"key2" : @"value2", @"key2b" : @"value2b"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc3", @{@"key3b" : @"value3b"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc4", @{@"key4" : @"value4"} ]
      ]));
}

- (void)testGetDocumentWhileOnlineServerOnly {
  FIRDocumentReference *doc = [self documentRef];

  // set document to a known value
  NSDictionary<NSString *, id> *initialData = @{@"key" : @"value"};
  [self writeDocumentRef:doc data:initialData];

  // get doc and ensure that it exists, is *not* from the cache, and matches
  // the initialData.
  FIRDocumentSnapshot *result =
      [self readDocumentForRef:doc options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceServer]];
  XCTAssertTrue(result.exists);
  XCTAssertFalse(result.metadata.fromCache);
  XCTAssertFalse(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(result.data, initialData);
}

- (void)testGetCollectionWhileOnlineServerOnly {
  FIRCollectionReference *col = [self collectionRef];

  // set a few documents to a known value
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *initialDocs = @{
    @"doc1" : @{@"key1" : @"value1"},
    @"doc2" : @{@"key2" : @"value2"},
    @"doc3" : @{@"key3" : @"value3"},
  };
  [self writeAllDocuments:initialDocs toCollection:col];

  // get docs and ensure they are *not* from the cache, and matches the
  // initialData.
  FIRQuerySnapshot *result =
      [self readDocumentSetForRef:col options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceServer]];
  XCTAssertFalse(result.metadata.fromCache);
  XCTAssertFalse(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(FIRQuerySnapshotGetData(result), (@[
                          @{@"key1" : @"value1"},
                          @{@"key2" : @"value2"},
                          @{@"key3" : @"value3"},
                        ]));
  XCTAssertEqualObjects(FIRQuerySnapshotGetDocChangesData(result), (@[
                          @[ @(FIRDocumentChangeTypeAdded), @"doc1", @{@"key1" : @"value1"} ],
                          @[ @(FIRDocumentChangeTypeAdded), @"doc2", @{@"key2" : @"value2"} ],
                          @[ @(FIRDocumentChangeTypeAdded), @"doc3", @{@"key3" : @"value3"} ]
                        ]));
}

- (void)testGetDocumentWhileOfflineServerOnly {
  FIRDocumentReference *doc = [self documentRef];

  // set document to a known value
  NSDictionary<NSString *, id> *initialData = @{@"key1" : @"value1"};
  [self writeDocumentRef:doc data:initialData];

  // go offline for the rest of this test
  [self disableNetwork];

  // attempt to get doc and ensure it cannot be retreived
  XCTestExpectation *failedGetDocCompletion = [self expectationWithDescription:@"failedGetDoc"];
  [doc getDocumentWithOptions:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceServer]
                   completion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
                     XCTAssertNotNil(error);
                     XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
                     XCTAssertEqual(error.code, FIRFirestoreErrorCodeUnavailable);
                     [failedGetDocCompletion fulfill];
                   }];
  [self awaitExpectations];
}

- (void)testGetCollectionWhileOfflineServerOnly {
  FIRCollectionReference *col = [self collectionRef];

  // set a few documents to a known value
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *initialDocs = @{
    @"doc1" : @{@"key1" : @"value1"},
    @"doc2" : @{@"key2" : @"value2"},
    @"doc3" : @{@"key3" : @"value3"},
  };
  [self writeAllDocuments:initialDocs toCollection:col];

  // go offline for the rest of this test
  [self disableNetwork];

  // attempt to get docs and ensure they cannot be retreived
  XCTestExpectation *failedGetDocsCompletion = [self expectationWithDescription:@"failedGetDocs"];
  [col getDocumentsWithOptions:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceServer]
                    completion:^(FIRQuerySnapshot *snapshot, NSError *error) {
                      XCTAssertNotNil(error);
                      XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
                      XCTAssertEqual(error.code, FIRFirestoreErrorCodeUnavailable);
                      [failedGetDocsCompletion fulfill];
                    }];
  [self awaitExpectations];
}

- (void)testGetDocumentWhileOfflineWithDifferentGetOptions {
  FIRDocumentReference *doc = [self documentRef];

  // set document to a known value
  NSDictionary<NSString *, id> *initialData = @{@"key1" : @"value1"};
  [self writeDocumentRef:doc data:initialData];

  // go offline for the rest of this test
  [self disableNetwork];

  // update the doc (though don't wait for a server response. We're offline; so
  // that ain't happening!). This allows us to further distinguished cached vs
  // server responses below.
  NSDictionary<NSString *, id> *newData = @{@"key2" : @"value2"};
  [doc setData:newData
      completion:^(NSError *_Nullable error) {
        XCTAssertTrue(false, "Because we're offline, this should never occur.");
      }];

  // Create an initial listener for this query (to attempt to disrupt the gets below) and wait for
  // the listener to deliver its initial snapshot before continuing.
  XCTestExpectation *listenerReady = [self expectationWithDescription:@"listenerReady"];
  [doc addSnapshotListener:^(FIRDocumentSnapshot *snapshot, NSError *error) {
    [listenerReady fulfill];
  }];
  [self awaitExpectations];

  // get doc (from cache) and ensure it exists, *is* from the cache, and
  // matches the newData.
  FIRDocumentSnapshot *result =
      [self readDocumentForRef:doc options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceCache]];
  XCTAssertTrue(result.exists);
  XCTAssertTrue(result.metadata.fromCache);
  XCTAssertTrue(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(result.data, newData);

  // attempt to get doc (with default get options)
  result =
      [self readDocumentForRef:doc options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceDefault]];
  XCTAssertTrue(result.exists);
  XCTAssertTrue(result.metadata.fromCache);
  XCTAssertTrue(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(result.data, newData);

  // attempt to get doc (from the server) and ensure it cannot be retreived
  XCTestExpectation *failedGetDocCompletion = [self expectationWithDescription:@"failedGetDoc"];
  [doc getDocumentWithOptions:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceServer]
                   completion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
                     XCTAssertNotNil(error);
                     XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
                     XCTAssertEqual(error.code, FIRFirestoreErrorCodeUnavailable);
                     [failedGetDocCompletion fulfill];
                   }];
  [self awaitExpectations];
}

- (void)testGetCollectionWhileOfflineWithDifferentGetOptions {
  FIRCollectionReference *col = [self collectionRef];

  // set a few documents to a known value
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *initialDocs = @{
    @"doc1" : @{@"key1" : @"value1"},
    @"doc2" : @{@"key2" : @"value2"},
    @"doc3" : @{@"key3" : @"value3"},
  };
  [self writeAllDocuments:initialDocs toCollection:col];

  // go offline for the rest of this test
  [self disableNetwork];

  // update the docs (though don't wait for a server response. We're offline; so
  // that ain't happening!). This allows us to further distinguished cached vs
  // server responses below.
  [[col documentWithPath:@"doc2"] setData:@{@"key2b" : @"value2b"} options:FIRSetOptions.merge];
  [[col documentWithPath:@"doc3"] setData:@{@"key3b" : @"value3b"}];
  [[col documentWithPath:@"doc4"] setData:@{@"key4" : @"value4"}];

  // Create an initial listener for this query (to attempt to disrupt the gets
  // below) and wait for the listener to deliver its initial snapshot before
  // continuing.
  XCTestExpectation *listenerReady = [self expectationWithDescription:@"listenerReady"];
  [col addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
    [listenerReady fulfill];
  }];
  [self awaitExpectations];

  // get docs (from cache) and ensure they *are* from the cache, and
  // matches the updated data.
  FIRQuerySnapshot *result =
      [self readDocumentSetForRef:col options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceCache]];
  XCTAssertTrue(result.metadata.fromCache);
  XCTAssertTrue(result.metadata.hasPendingWrites);
  XCTAssertEqualObjects(FIRQuerySnapshotGetData(result), (@[
                          @{@"key1" : @"value1"}, @{@"key2" : @"value2", @"key2b" : @"value2b"},
                          @{@"key3b" : @"value3b"}, @{@"key4" : @"value4"}
                        ]));
  XCTAssertEqualObjects(
      FIRQuerySnapshotGetDocChangesData(result), (@[
        @[ @(FIRDocumentChangeTypeAdded), @"doc1", @{@"key1" : @"value1"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc2", @{@"key2" : @"value2", @"key2b" : @"value2b"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc3", @{@"key3b" : @"value3b"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc4", @{@"key4" : @"value4"} ]
      ]));

  // attempt to get docs (with default get options)
  result = [self readDocumentSetForRef:col
                               options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceDefault]];
  XCTAssertTrue(result.metadata.fromCache);
  XCTAssertEqualObjects(FIRQuerySnapshotGetData(result), (@[
                          @{@"key1" : @"value1"}, @{@"key2" : @"value2", @"key2b" : @"value2b"},
                          @{@"key3b" : @"value3b"}, @{@"key4" : @"value4"}
                        ]));
  XCTAssertEqualObjects(
      FIRQuerySnapshotGetDocChangesData(result), (@[
        @[ @(FIRDocumentChangeTypeAdded), @"doc1", @{@"key1" : @"value1"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc2", @{@"key2" : @"value2", @"key2b" : @"value2b"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc3", @{@"key3b" : @"value3b"} ],
        @[ @(FIRDocumentChangeTypeAdded), @"doc4", @{@"key4" : @"value4"} ]
      ]));

  // attempt to get docs (from the server) and ensure they cannot be retreived
  XCTestExpectation *failedGetDocsCompletion = [self expectationWithDescription:@"failedGetDocs"];
  [col getDocumentsWithOptions:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceServer]
                    completion:^(FIRQuerySnapshot *snapshot, NSError *error) {
                      XCTAssertNotNil(error);
                      XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
                      XCTAssertEqual(error.code, FIRFirestoreErrorCodeUnavailable);
                      [failedGetDocsCompletion fulfill];
                    }];
  [self awaitExpectations];
}

- (void)testGetNonExistingDocWhileOnlineWithDefaultGetOptions {
  FIRDocumentReference *doc = [self documentRef];

  // get doc and ensure that it does not exist and is *not* from the cache.
  FIRDocumentSnapshot *snapshot = [self readDocumentForRef:doc];
  XCTAssertFalse(snapshot.exists);
  XCTAssertFalse(snapshot.metadata.fromCache);
  XCTAssertFalse(snapshot.metadata.hasPendingWrites);
}

- (void)testGetNonExistingCollectionWhileOnlineWithDefaultGetOptions {
  FIRCollectionReference *col = [self collectionRef];

  // get collection and ensure it's empty and that it's *not* from the cache.
  FIRQuerySnapshot *snapshot = [self readDocumentSetForRef:col];
  XCTAssertEqual(snapshot.count, 0);
  XCTAssertEqual(snapshot.documentChanges.count, 0);
  XCTAssertFalse(snapshot.metadata.fromCache);
  XCTAssertFalse(snapshot.metadata.hasPendingWrites);
}

- (void)testGetNonExistingDocWhileOfflineWithDefaultGetOptions {
  FIRDocumentReference *doc = [self documentRef];

  // go offline for the rest of this test
  [self disableNetwork];

  // attempt to get doc. Currently, this is expected to fail. In the future, we
  // might consider adding support for negative cache hits so that we know
  // certain documents *don't* exist.
  XCTestExpectation *getNonExistingDocCompletion =
      [self expectationWithDescription:@"getNonExistingDoc"];
  [doc getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
    XCTAssertEqual(error.code, FIRFirestoreErrorCodeUnavailable);
    [getNonExistingDocCompletion fulfill];
  }];
  [self awaitExpectations];
}

- (void)testGetNonExistingCollectionWhileOfflineWithDefaultGetOptions {
  FIRCollectionReference *col = [self collectionRef];

  // go offline for the rest of this test
  [self disableNetwork];

  // get collection and ensure it's empty and that it *is* from the cache.
  FIRQuerySnapshot *snapshot = [self readDocumentSetForRef:col];
  XCTAssertEqual(snapshot.count, 0);
  XCTAssertEqual(snapshot.documentChanges.count, 0);
  XCTAssertTrue(snapshot.metadata.fromCache);
  XCTAssertFalse(snapshot.metadata.hasPendingWrites);
}

- (void)testGetNonExistingDocWhileOnlineCacheOnly {
  FIRDocumentReference *doc = [self documentRef];

  // attempt to get doc. Currently, this is expected to fail. In the future, we
  // might consider adding support for negative cache hits so that we know
  // certain documents *don't* exist.
  XCTestExpectation *getNonExistingDocCompletion =
      [self expectationWithDescription:@"getNonExistingDoc"];
  [doc getDocumentWithOptions:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceCache]
                   completion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
                     XCTAssertNotNil(error);
                     XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
                     XCTAssertEqual(error.code, FIRFirestoreErrorCodeUnavailable);
                     [getNonExistingDocCompletion fulfill];
                   }];
  [self awaitExpectations];
}

- (void)testGetNonExistingCollectionWhileOnlineCacheOnly {
  FIRCollectionReference *col = [self collectionRef];

  // get collection and ensure it's empty and that it *is* from the cache.
  FIRQuerySnapshot *snapshot =
      [self readDocumentSetForRef:col options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceCache]];
  XCTAssertEqual(snapshot.count, 0);
  XCTAssertEqual(snapshot.documentChanges.count, 0);
  XCTAssertTrue(snapshot.metadata.fromCache);
  XCTAssertFalse(snapshot.metadata.hasPendingWrites);
}

- (void)testGetNonExistingDocWhileOfflineCacheOnly {
  FIRDocumentReference *doc = [self documentRef];

  // go offline for the rest of this test
  [self disableNetwork];

  // attempt to get doc. Currently, this is expected to fail. In the future, we
  // might consider adding support for negative cache hits so that we know
  // certain documents *don't* exist.
  XCTestExpectation *getNonExistingDocCompletion =
      [self expectationWithDescription:@"getNonExistingDoc"];
  [doc getDocumentWithOptions:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceCache]
                   completion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
                     XCTAssertNotNil(error);
                     XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
                     XCTAssertEqual(error.code, FIRFirestoreErrorCodeUnavailable);
                     [getNonExistingDocCompletion fulfill];
                   }];
  [self awaitExpectations];
}

- (void)testGetNonExistingCollectionWhileOfflineCacheOnly {
  FIRCollectionReference *col = [self collectionRef];

  // go offline for the rest of this test
  [self disableNetwork];

  // get collection and ensure it's empty and that it *is* from the cache.
  FIRQuerySnapshot *snapshot =
      [self readDocumentSetForRef:col options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceCache]];
  XCTAssertEqual(snapshot.count, 0);
  XCTAssertEqual(snapshot.documentChanges.count, 0);
  XCTAssertTrue(snapshot.metadata.fromCache);
  XCTAssertFalse(snapshot.metadata.hasPendingWrites);
}

- (void)testGetNonExistingDocWhileOnlineServerOnly {
  FIRDocumentReference *doc = [self documentRef];

  // get doc and ensure that it does not exist and is *not* from the cache.
  FIRDocumentSnapshot *snapshot =
      [self readDocumentForRef:doc options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceServer]];
  XCTAssertFalse(snapshot.exists);
  XCTAssertFalse(snapshot.metadata.fromCache);
  XCTAssertFalse(snapshot.metadata.hasPendingWrites);
}

- (void)testGetNonExistingCollectionWhileOnlineServerOnly {
  FIRCollectionReference *col = [self collectionRef];

  // get collection and ensure that it's empty and that it's *not* from the cache.
  FIRQuerySnapshot *snapshot =
      [self readDocumentSetForRef:col options:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceServer]];
  XCTAssertEqual(snapshot.count, 0);
  XCTAssertEqual(snapshot.documentChanges.count, 0);
  XCTAssertFalse(snapshot.metadata.fromCache);
  XCTAssertFalse(snapshot.metadata.hasPendingWrites);
}

- (void)testGetNonExistingDocWhileOfflineServerOnly {
  FIRDocumentReference *doc = [self documentRef];

  // go offline for the rest of this test
  [self disableNetwork];

  // attempt to get doc. Currently, this is expected to fail. In the future, we
  // might consider adding support for negative cache hits so that we know
  // certain documents *don't* exist.
  XCTestExpectation *getNonExistingDocCompletion =
      [self expectationWithDescription:@"getNonExistingDoc"];
  [doc getDocumentWithOptions:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceServer]
                   completion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
                     XCTAssertNotNil(error);
                     XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
                     XCTAssertEqual(error.code, FIRFirestoreErrorCodeUnavailable);
                     [getNonExistingDocCompletion fulfill];
                   }];
  [self awaitExpectations];
}

- (void)testGetNonExistingCollectionWhileOfflineServerOnly {
  FIRCollectionReference *col = [self collectionRef];

  // go offline for the rest of this test
  [self disableNetwork];

  // attempt to get collection and ensure that it cannot be retreived
  XCTestExpectation *failedGetDocsCompletion = [self expectationWithDescription:@"failedGetDocs"];
  [col getDocumentsWithOptions:[[[FIRGetOptions alloc] init] optionsWithSource:FIRGetSourceServer]
                    completion:^(FIRQuerySnapshot *snapshot, NSError *error) {
                      XCTAssertNotNil(error);
                      XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
                      XCTAssertEqual(error.code, FIRFirestoreErrorCodeUnavailable);
                      [failedGetDocsCompletion fulfill];
                    }];
  [self awaitExpectations];
}

@end
