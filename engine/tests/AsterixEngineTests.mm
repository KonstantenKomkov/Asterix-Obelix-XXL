#import <XCTest/XCTest.h>

#include "asterix/engine.h"

@interface AsterixEngineTests : XCTestCase
@end

@implementation AsterixEngineTests

- (void)testCoreVersionMatchesPublicHeader {
  XCTAssertEqual(asterix_engine_core_version(), ASTERIX_ENGINE_CORE_VERSION);
}

@end
