//
//  RLXEngineEnvironment.m
//  RelaxinEngine
//

#import "RLXEngineEnvironment.h"

#import "../../RelaxinPostJailbreak/Actions/RLXPostJailbreakActionRunner.h"

BOOL RLXInstalledThroughTrollStore(void) {
    return RLXPostJailbreakInstalledThroughTrollStore();
}
