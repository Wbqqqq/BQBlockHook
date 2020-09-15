//
//  main.m
//  BQBlockHookDemo
//
//  Created by wangbingquan on 2020/9/14.
//  Copyright © 2020 wangbingquan. All rights reserved.
//


#import "NSObject+BQBlockHook.h"

struct time {
    // requires BLOCK_HAS_SIGNATURE
    int a ;
    int b;// contents depend on BLOCK_HAS_EXTENDED_LAYOUT
};

int main(int argc, char * argv[]) {
   
    void (^test)(void) = ^()
     {
         NSLog(@"哈哈");
//         int a = 20;
        
     };
//
     [test hookWithMode:BQBlockHookModeAfter | BQBlockHookAutomaticRemoval usingBlock:^(NSInvocation *invocation, int a){
         // Hook 改参数
         NSLog(@"被我hook了1");
     }];

    test();
    
    
//    test(30);
//    
//    [test hookWithMode:BQBlockHookModeBefore | BQBlockHookAutomaticRemoval usingBlock:^(NSInvocation *invocation, int a){
//        // Hook 改参数
//        NSLog(@"被我hook了");
//    }];
//    
//    test(30);
    
    void (^StructReturnBlock)(struct time test) = ^(struct time test)
           {
               NSLog(@"被修改参数之后%d",test.a);

           };

           [StructReturnBlock hookWithMode:BQBlockHookModeBefore usingBlock:^(NSInvocation *invocation, struct time test){
               // Hook 改参数
               test.a = 100;
               [invocation setArgument:&test atIndex:1];
               NSLog(@"被我hook了2");
           }];

    struct time stu1={12,12};
     StructReturnBlock(stu1);
    
    return 0;
    
    
}

//void test(){

//}
