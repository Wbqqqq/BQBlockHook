//
//  NSObject+BQBlockHook.m
//  BQBlockHookDemo
//
//  Created by wangbingquan on 2020/9/14.
//  Copyright © 2020 wangbingquan. All rights reserved.
//

#import "NSObject+BQBlockHook.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/vm_map.h>
#import <mach/mach_init.h>

#define BQHookMethod(selector, func) { Class cls = NSClassFromString(@"NSBlock");Method method = class_getInstanceMethod([NSObject class], selector); \
Method swizzledSel = class_getInstanceMethod([NSObject class], func); \
BOOL success = class_addMethod(cls, selector, method_getImplementation(swizzledSel), method_getTypeEncoding(method)); \
if (!success) { class_replaceMethod(cls, selector, method_getImplementation(swizzledSel), method_getTypeEncoding(method));}}

typedef NS_OPTIONS(int, BQBlockFlage) {
    BQ_BLOCK_DEALLOCATING =      (0x0001),  // runtime
    BQ_BLOCK_REFCOUNT_MASK =     (0xfffe),  // runtime
    BQ_BLOCK_NEEDS_FREE =        (1 << 24), // runtime
    BQ_BLOCK_HAS_COPY_DISPOSE =  (1 << 25), // compiler
    BQ_BLOCK_HAS_CTOR =          (1 << 26), // compiler: helpers have C++ de
    BQ_BLOCK_IS_GC =             (1 << 27), // runtime
    BQ_BLOCK_IS_GLOBAL =         (1 << 28), // compiler
    BQ_BLOCK_USE_STRET =         (1 << 29), // compiler: undefined if LOCK_HAS_SIGNATURE
    BQ_BLOCK_HAS_SIGNATURE  =    (1 << 30), // compiler
    BQ_BLOCK_HAS_EXTENDED_LAYOUT=(1 << 31)  // compiler
};

struct BQBlock_impl {
    void *isa;
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct BQBlock_descriptor_1 *descriptor;
};

typedef struct BQBlock_impl *BQBlock;

struct BQBlock_descriptor_1 {
    uintptr_t reserved;
    uintptr_t size;
};

struct BQBlock_descriptor_2 {
    void (*copy)(void *dst, const void *src);
    void (*dispose)(const void *);
};

struct BQBlock_descriptor_3 {
    const char *signature;
    const char *layout;
};


//获取descriptor_3
static struct BQBlock_descriptor_3 * block_descriptor_3(BQBlock block) {
    if (!(block->flags & BQ_BLOCK_HAS_SIGNATURE)) {
        return NULL;
    }
    uint8_t *desc = (uint8_t *)block->descriptor;
    desc += sizeof(struct BQBlock_descriptor_1);
    if (block->flags & BQ_BLOCK_HAS_COPY_DISPOSE) {
        desc += sizeof(struct BQBlock_descriptor_2);
    }
    return (struct BQBlock_descriptor_3 *)desc;
}

static IMP _bq_getMsgForward(const char *methodTypes) {
    IMP msgForwardIMP = _objc_msgForward;
#if !defined(__arm64__)
    if (methodTypes[0] == '{') {
        NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:methodTypes];
        if ([methodSignature.debugDescription rangeOfString:@"is special struct return? YES"].location != NSNotFound) {
            msgForwardIMP = (IMP)_objc_msgForward_stret;
        }
    }
#endif
    return msgForwardIMP;
}

vm_prot_t protectInvokeVMIfNeed(void *address) {
    vm_address_t addr = (vm_address_t)address;
    vm_size_t vmsize = 0;
    mach_port_t object = 0;
#if defined(__LP64__) && __LP64__
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCnt = VM_REGION_BASIC_INFO_COUNT_64;
    kern_return_t ret = vm_region_64(mach_task_self(), &addr, &vmsize, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &infoCnt, &object);
#else
    vm_region_basic_info_data_t info;
    mach_msg_type_number_t infoCnt = VM_REGION_BASIC_INFO_COUNT;
    kern_return_t ret = vm_region(mach_task_self(), &addr, &vmsize, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &infoCnt, &object);
#endif
    if (ret != KERN_SUCCESS) {
        NSLog(@"vm_region block invoke pointer failed! ret:%d, addr:%p", ret, address);
        return VM_PROT_NONE;
    }
    vm_prot_t protection = info.protection;
    if ((protection&VM_PROT_WRITE) == 0) {
        ret = vm_protect(mach_task_self(), (vm_address_t)address, sizeof(address), false, protection|VM_PROT_WRITE);
        if (ret != KERN_SUCCESS) {
            NSLog(@"vm_protect block invoke pointer VM_PROT_WRITE failed! ret:%d, addr:%p", ret, address);
            return VM_PROT_NONE;
        }
    }
    return protection;
}

bool ReplaceBlockInvoke(struct BQBlock_impl *block, void *replacement) {
    void *address = &(block->invoke);
    vm_prot_t origProtection = protectInvokeVMIfNeed(address);
    if (origProtection == VM_PROT_NONE) {
        return NO;
    }
    block->invoke = replacement;
    if ((origProtection&VM_PROT_WRITE) == 0) {
        kern_return_t ret = vm_protect(mach_task_self(), (vm_address_t)address, sizeof(address), false, origProtection);
        if (ret != KERN_SUCCESS) {
            NSLog(@"vm_protect block invoke pointer REVERT failed! ret:%d, addr:%p", ret, address);
        }
    }
    return YES;
}



@implementation NSObject (BQBlockHook)

-(void)methodSwizzling{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BQHookMethod(@selector(methodSignatureForSelector:), @selector(bh_methodSignatureForSelector:));
        BQHookMethod(@selector(forwardInvocation:), @selector(bh_forwardInvocation:));
    });
}



-(NSMethodSignature * )bh_methodSignatureForSelector:(SEL)selector{
    struct BQBlock_descriptor_3 *desc_3 = block_descriptor_3((__bridge void *)self);
    return [NSMethodSignature signatureWithObjCTypes:desc_3->signature];
}

-(void)bh_forwardInvocation:(NSInvocation *)invocation{
  
   struct BQBlock_impl *originBlock = (__bridge void *)invocation.target;
    
   struct BQBlock_descriptor_3 *desc_3 = block_descriptor_3((__bridge BQBlock)(self.aspectBlock));
    
   NSMethodSignature *aspectBlockSignature = [NSMethodSignature signatureWithObjCTypes:desc_3->signature];
    
   NSInvocation *blockInvocation = [NSInvocation invocationWithMethodSignature:aspectBlockSignature];
    
   if (aspectBlockSignature.numberOfArguments > 1) {
       [blockInvocation setArgument:(void *)&invocation atIndex:1];
   }
    
   NSUInteger numberOfArguments = MIN(aspectBlockSignature.numberOfArguments,
                                      invocation.methodSignature.numberOfArguments + 1);
   void *tmpArg = NULL;
   for (NSUInteger idx = 2; idx < numberOfArguments; idx++) {
       const char *type = [invocation.methodSignature getArgumentTypeAtIndex:idx - 1];
       NSUInteger argsSize;
       NSGetSizeAndAlignment(type, &argsSize, NULL);
       if (!(tmpArg = realloc(tmpArg, argsSize))) {
           NSLog(@"fail allocate memory for block arg");
           return;
       }
       [invocation getArgument:tmpArg atIndex:idx - 1];
       [blockInvocation setArgument:tmpArg atIndex:idx];
   }
        
   BQBlockHookMode mode = self.mode;
   
   if(mode & BQBlockHookModeBefore){
      [blockInvocation invokeWithTarget:self.aspectBlock];
      ReplaceBlockInvoke(originBlock,[self originInvoke]);
      [invocation invokeWithTarget:(__bridge id _Nonnull)(originBlock)];
      ReplaceBlockInvoke(originBlock,(void *)_bq_getMsgForward(desc_3->signature));
   }else if(mode & BQBlockHookModeInstead){
       [blockInvocation invokeWithTarget:self.aspectBlock];
   }else if(mode & BQBlockHookModeAfter){
       ReplaceBlockInvoke(originBlock,[self originInvoke]);
       [invocation invokeWithTarget:(__bridge id _Nonnull)(originBlock)];
       ReplaceBlockInvoke(originBlock,(void *)_bq_getMsgForward(desc_3->signature));
       [blockInvocation invokeWithTarget:self.aspectBlock];
   }
    
    
   if(mode & BQBlockHookAutomaticRemoval){
       ReplaceBlockInvoke(originBlock,[self originInvoke]);
   }
}


-(void)setMode:(BQBlockHookMode)mode{
    objc_setAssociatedObject(self, @selector(mode), @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BQBlockHookMode)mode
{
    return [objc_getAssociatedObject(self, @selector(mode)) integerValue];
}

-(void)setAspectBlock:(id)aspectBlock{
    objc_setAssociatedObject(self, @selector(aspectBlock), aspectBlock, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

-(id)aspectBlock{
   return objc_getAssociatedObject(self, @selector(aspectBlock));
}

-(void)setOriginInvoke:(void *)originInvoke {
    objc_setAssociatedObject(self, @selector(originInvoke), (__bridge id)originInvoke, OBJC_ASSOCIATION_ASSIGN);
}

-(void *)originInvoke{
    return (__bridge void *)(objc_getAssociatedObject(self, @selector(originInvoke)));
}

- (BOOL)block_checkValid {
    return [self isKindOfClass:NSClassFromString(@"NSBlock")];
}


-(void)hookWithMode:(BQBlockHookMode)mode usingBlock:(id)aspectBlock{
    
    NSAssert([self block_checkValid], @"it must extend NSBlock");
    NSAssert(aspectBlock, @"you should not use hookblock");
    //保存hook状态
    [self setMode:mode];
    [self setAspectBlock:aspectBlock];
    [self blockhook];
    
}



-(void)blockhook{
    [self methodSwizzling];
    struct BQBlock_impl *block = (__bridge struct BQBlock_impl *)self;
    //保存原实现
    [self setOriginInvoke:block->invoke];
    //替换实现
    struct BQBlock_descriptor_3 *desc_3 = block_descriptor_3(block);
    
    ReplaceBlockInvoke(block, (void *)_bq_getMsgForward(desc_3->signature));
  
//    block->invoke = (void *)_bq_getMsgForward(desc_3->signature);
//    uint8_t *desc = (uint8_t *)block->isa;
//    desc += sizeof(void *);
//    desc += sizeof(int);
//    desc += sizeof(int);
//    
//    char *p = (char *)&block;
//    *(p+32)=(void *)_bq_getMsgForward(desc_3->signature);
//
////    printf("offset b: %ld\n", OFFSET(block, invoke));
//    int *p = &desc;
//
//    void * invoke = (void *)desc;
//    invoke = (void *)_bq_getMsgForward(desc_3->signature);
}



@end
