/*
 * CocosBuilder: http://www.cocosbuilder.com
 *
 * Copyright (c) 2012 Zynga Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "CCBReaderInternal.h"
#import "CCBReaderInternalV1.h"
#import "PlugInManager.h"
#import "PlugInNode.h"
#import "NodeInfo.h"
#import "CCBWriterInternal.h"
#import "TexturePropertySetter.h"
#import "CCBGlobals.h"
#import "AppDelegate.h"
#import "ResourceManager.h"
#import "NodeGraphPropertySetter.h"
#import "PositionPropertySetter.h"
#import "StringPropertySetter.h"
#import "CCNode+NodeInfo.h"
#import "NodePhysicsBody.h"

// Old positioning constants
enum
{
    kCCBPositionTypeRelativeBottomLeft,
    kCCBPositionTypeRelativeTopLeft,
    kCCBPositionTypeRelativeTopRight,
    kCCBPositionTypeRelativeBottomRight,
    kCCBPositionTypePercent,
    kCCBPositionTypeMultiplyResolution,
};

enum
{
    kCCBSizeTypeAbsolute,
    kCCBSizeTypePercent,
    kCCBSizeTypeRelativeContainer,
    kCCBSizeTypeHorizontalPercent,
    kCCBSzieTypeVerticalPercent,
    kCCBSizeTypeMultiplyResolution,
};

NSDictionary* renamedProperties = NULL;

@implementation CCBReaderInternal

+ (NSPoint) deserializePoint:(id) val
{
    float x = [[val objectAtIndex:0] floatValue];
    float y = [[val objectAtIndex:1] floatValue];
    return NSMakePoint(x,y);
}

+ (NSSize) deserializeSize:(id) val
{
    float w = [[val objectAtIndex:0] floatValue];
    float h = [[val objectAtIndex:1] floatValue];
    return NSMakeSize(w, h);
}

+ (float) deserializeFloat:(id) val
{
    return [val floatValue];
}

+ (int) deserializeInt:(id) val
{
    return [val intValue];
}

+ (BOOL) deserializeBool:(id) val
{
    return [val boolValue];
}

+ (ccColor3B) deserializeColor3:(id) val
{
    ccColor3B c;
    c.r = [[val objectAtIndex:0] intValue];
    c.g = [[val objectAtIndex:1] intValue];
    c.b = [[val objectAtIndex:2] intValue];
    return c;
}

+ (ccColor4B) deserializeColor4:(id) val
{
    ccColor4B c;
    c.r = [[val objectAtIndex:0] intValue];
    c.g = [[val objectAtIndex:1] intValue];
    c.b = [[val objectAtIndex:2] intValue];
    c.a = [[val objectAtIndex:3] intValue];
    return c;
}

+ (ccColor4F) deserializeColor4F:(id) val
{
    ccColor4F c;
    c.r = [[val objectAtIndex:0] floatValue];
    c.g = [[val objectAtIndex:1] floatValue];
    c.b = [[val objectAtIndex:2] floatValue];
    c.a = [[val objectAtIndex:3] floatValue];
    return c;
}

+ (ccBlendFunc) deserializeBlendFunc:(id) val
{
    ccBlendFunc bf;
    bf.src = [[val objectAtIndex:0] intValue];
    bf.dst = [[val objectAtIndex:1] intValue];
    return bf;
}

+ (void) setProp:(NSString*)name ofType:(NSString*)type toValue:(id)serializedValue forNode:(CCNode*)node parentSize:(CGSize)parentSize
{
    // Handle removed ignoreAnchorPointForPosition property
    if ([name isEqualToString:@"ignoreAnchorPointForPosition"]) return;
    
    // Fetch info and extra properties
    NodeInfo* nodeInfo = node.userObject;
    NSMutableDictionary* extraProps = nodeInfo.extraProps;
    
    if ([type isEqualToString:@"Position"])
    {
        float x = [[serializedValue objectAtIndex:0] floatValue];
        float y = [[serializedValue objectAtIndex:1] floatValue];
        CCPositionType posType = CCPositionTypePoints;
        if ([(NSArray*)serializedValue count] == 3)
        {
            // Position is stored in old format - do conversion
            int oldPosType = [[serializedValue objectAtIndex:2] intValue];
            if (oldPosType == kCCBPositionTypeRelativeBottomLeft) posType.corner = CCPositionReferenceCornerBottomLeft;
            else if (oldPosType == kCCBPositionTypeRelativeTopLeft) posType.corner = CCPositionReferenceCornerTopLeft;
            else if (oldPosType == kCCBPositionTypeRelativeTopRight) posType.corner = CCPositionReferenceCornerTopRight;
            else if (oldPosType == kCCBPositionTypeRelativeBottomRight) posType.corner = CCPositionReferenceCornerBottomRight;
            else if (oldPosType == kCCBPositionTypePercent)
            {
                posType = CCPositionTypeNormalized;
                x /= 100.0;
                y /= 100.0;
            }
            else if (oldPosType == kCCBPositionTypeMultiplyResolution)
            {
                posType = CCPositionTypeScaled;
            }
        }
        else if ([(NSArray*)serializedValue count] == 5)
        {
            // New positioning type
            posType.corner = [[serializedValue objectAtIndex:2] intValue];
            posType.xUnit = [[serializedValue objectAtIndex:3] intValue];
            posType.yUnit = [[serializedValue objectAtIndex:4] intValue];
        }
        [PositionPropertySetter setPosition:NSMakePoint(x, y) type:posType forNode:node prop:name];
    }
    else if ([type isEqualToString:@"Point"]
        || [type isEqualToString:@"PointLock"])
    {
        NSPoint pt = [CCBReaderInternal deserializePoint: serializedValue];
		
        [node setValue:[NSValue valueWithPoint:pt] forKey:name];
    }
    else if ([type isEqualToString:@"Size"])
    {
        float w = [[serializedValue objectAtIndex:0] floatValue];
        float h = [[serializedValue objectAtIndex:1] floatValue];
        
        CCContentSizeType sizeType = CCContentSizeTypePoints;
        if ([(NSArray*)serializedValue count] == 3)
        {
            // Convert old content size type
            int oldSizeType = [[serializedValue objectAtIndex:2] intValue];
            if (oldSizeType == kCCBSizeTypePercent)
            {
                sizeType = CCContentSizeTypeNormalized;
                w /= 100.0f;
                h /= 100.0f;
            }
            else if (oldSizeType == kCCBSizeTypeRelativeContainer)
            {
                sizeType.widthUnit = CCContentSizeUnitInsetPoints;
                sizeType.heightUnit = CCContentSizeUnitInsetPoints;
            }
            else if (oldSizeType == kCCBSizeTypeHorizontalPercent)
            {
                sizeType.widthUnit = CCContentSizeUnitNormalized;
                w /= 100.0f;
            }
            else if (oldSizeType == kCCBSzieTypeVerticalPercent)
            {
                sizeType.heightUnit = CCContentSizeUnitNormalized;
                h /= 100.0f;
            }
            else if (oldSizeType == kCCBSizeTypeMultiplyResolution)
            {
                sizeType = CCContentSizeTypeScaled;
            }
        }
        else if ([(NSArray*)serializedValue count] == 4)
        {
            // Uses new content size type
            sizeType.widthUnit = [[serializedValue objectAtIndex:2] intValue];
            sizeType.heightUnit = [[serializedValue objectAtIndex:3] intValue];
        }
        
        NSSize size =  NSMakeSize(w, h);
        [PositionPropertySetter setSize:size type:sizeType forNode:node prop:name];
    }
    else if ([type isEqualToString:@"Scale"]
             || [type isEqualToString:@"ScaleLock"])
    {
        float x = [[serializedValue objectAtIndex:0] floatValue];
        float y = [[serializedValue objectAtIndex:1] floatValue];
        int scaleType = 0;
        if ([(NSArray*)serializedValue count] >= 3)
        {
            [extraProps setValue:[serializedValue objectAtIndex:2] forKey:[NSString stringWithFormat:@"%@Lock",name]];
            if ([(NSArray*)serializedValue count] == 4)
            {
                scaleType = [[serializedValue objectAtIndex:3] intValue];
            }
        }
        [PositionPropertySetter setScaledX:x Y:y type:scaleType forNode:node prop:name];
    }
    else if ([type isEqualToString:@"FloatXY"])
    {
        float x = [[serializedValue objectAtIndex:0] floatValue];
        float y = [[serializedValue objectAtIndex:1] floatValue];
        [node setValue:[NSNumber numberWithFloat:x] forKey:[name stringByAppendingString:@"X"]];
        [node setValue:[NSNumber numberWithFloat:y] forKey:[name stringByAppendingString:@"Y"]];
    }
    else if ([type isEqualToString:@"Float"]
             || [type isEqualToString:@"Degrees"])
    {
        float f = [CCBReaderInternal deserializeFloat: serializedValue];
        [node setValue:[NSNumber numberWithFloat:f] forKey:name];
    }
    else if ([type isEqualToString:@"FloatScale"])
    {
        float f = 0;
        int type = 0;
        if ([serializedValue isKindOfClass:[NSNumber class]])
        {
            // Support for old files
            f = [serializedValue floatValue];
        }
        else
        {
            f = [[serializedValue objectAtIndex:0] floatValue];
            type = [[serializedValue objectAtIndex:1] intValue];
        }
        [PositionPropertySetter setFloatScale:f type:type forNode:node prop:name];
    }
    else if ([type isEqualToString:@"FloatVar"])
    {
        [node setValue:[serializedValue objectAtIndex:0] forKey:name];
        [node setValue:[serializedValue objectAtIndex:1] forKey:[NSString stringWithFormat:@"%@Var",name]];
    }
    else if ([type isEqualToString:@"Integer"]
             || [type isEqualToString:@"IntegerLabeled"]
             || [type isEqualToString:@"Byte"])
    {
        int d = [CCBReaderInternal deserializeInt: serializedValue];
        [node setValue:[NSNumber numberWithInt:d] forKey:name];
    }
    else if ([type isEqualToString:@"Check"])
    {
        BOOL check = [CCBReaderInternal deserializeBool:serializedValue];
        [node setValue:[NSNumber numberWithBool:check] forKey:name];
    }
    else if ([type isEqualToString:@"Flip"])
    {
        [node setValue:[serializedValue objectAtIndex:0] forKey:[NSString stringWithFormat:@"%@X",name]];
        [node setValue:[serializedValue objectAtIndex:1] forKey:[NSString stringWithFormat:@"%@Y",name]];
    }
    else if ([type isEqualToString:@"SpriteFrame"])
    {
        NSString* spriteSheetFile = [serializedValue objectAtIndex:0];
        NSString* spriteFile = [serializedValue objectAtIndex:1];
        if (!spriteSheetFile || [spriteSheetFile isEqualToString:@""])
        {
            spriteSheetFile = kCCBUseRegularFile;
        }
        
        [extraProps setObject:spriteSheetFile forKey:[NSString stringWithFormat:@"%@Sheet",name]];
        [extraProps setObject:spriteFile forKey:name];
        [TexturePropertySetter setSpriteFrameForNode:node andProperty:name withFile:spriteFile andSheetFile:spriteSheetFile];
    }
    else if ([type isEqualToString:@"Texture"])
    {
        NSString* spriteFile = serializedValue;
        if (!spriteFile) spriteFile = @"";
        [TexturePropertySetter setTextureForNode:node andProperty:name withFile:spriteFile];
        [extraProps setObject:spriteFile forKey:name];
    }
    else if ([type isEqualToString:@"Color3"])
    {
        ccColor3B c = [CCBReaderInternal deserializeColor3:serializedValue];
        NSValue* colorValue = [NSValue value:&c withObjCType:@encode(ccColor3B)];
        [node setValue:colorValue forKey:name];
    }
    else if ([type isEqualToString:@"Color4"])
    {
        ccColor4B c = [CCBReaderInternal deserializeColor4:serializedValue];
        NSValue* colorValue = [NSValue value:&c withObjCType:@encode(ccColor4B)];
        [node setValue:colorValue forKey:name];
    }
    else if ([type isEqualToString:@"Color4FVar"])
    {
        ccColor4F c = [CCBReaderInternal deserializeColor4F:[serializedValue objectAtIndex:0]];
        ccColor4F cVar = [CCBReaderInternal deserializeColor4F:[serializedValue objectAtIndex:1]];
        NSValue* cValue = [NSValue value:&c withObjCType:@encode(ccColor4F)];
        NSValue* cVarValue = [NSValue value:&cVar withObjCType:@encode(ccColor4F)];
        [node setValue:cValue forKey:name];
        [node setValue:cVarValue forKey:[NSString stringWithFormat:@"%@Var",name]];
    }
    else if ([type isEqualToString:@"Blendmode"])
    {
        ccBlendFunc bf = [CCBReaderInternal deserializeBlendFunc:serializedValue];
        NSValue* blendValue = [NSValue value:&bf withObjCType:@encode(ccBlendFunc)];
        [node setValue:blendValue forKey:name];
    }
    else if ([type isEqualToString:@"FntFile"])
    {
        NSString* fntFile = serializedValue;
        if (!fntFile) fntFile = @"";
        [TexturePropertySetter setFontForNode:node andProperty:name withFile:fntFile];
        [extraProps setObject:fntFile forKey:name];
    }
    else if ([type isEqualToString:@"Text"]
             || [type isEqualToString:@"String"])
    {
        NSString* str = NULL;
        BOOL localized = NO;
        
        if ([serializedValue isKindOfClass:[NSString class]])
        {
            str = serializedValue;
        }
        else
        {
            str = [serializedValue objectAtIndex:0];
            localized = [[serializedValue objectAtIndex:1] boolValue];
        }
        
        if (!str) str = @"";
        [StringPropertySetter setString:str forNode:node andProp:name];
        [StringPropertySetter setLocalized:localized forNode:node andProp:name];
    }
    else if ([type isEqualToString:@"FontTTF"])
    {
        NSString* str = serializedValue;
        if (!str) str = @"";
        [TexturePropertySetter setTtfForNode:node andProperty:name withFont:str];
    }
    else if ([type isEqualToString:@"Block"])
    {
        NSString* selector = [serializedValue objectAtIndex:0];
        NSNumber* target = [serializedValue objectAtIndex:1];
        if (!selector) selector = @"";
        if (!target) target = [NSNumber numberWithInt:0];
        [extraProps setObject: selector forKey:name];
        [extraProps setObject:target forKey:[NSString stringWithFormat:@"%@Target",name]];
    }
    else if ([type isEqualToString:@"BlockCCControl"])
    {
        NSString* selector = [serializedValue objectAtIndex:0];
        NSNumber* target = [serializedValue objectAtIndex:1];
        NSNumber* ctrlEvts = [serializedValue objectAtIndex:2];
        if (!selector) selector = @"";
        if (!target) target = [NSNumber numberWithInt:0];
        if (!ctrlEvts) ctrlEvts = [NSNumber numberWithInt:0];
        [extraProps setObject: selector forKey:name];
        [extraProps setObject:target forKey:[NSString stringWithFormat:@"%@Target",name]];
        [extraProps setObject:ctrlEvts forKey:[NSString stringWithFormat:@"%@CtrlEvts",name]];
    }
    else if ([type isEqualToString:@"CCBFile"])
    {
        NSString* ccbFile = serializedValue;
        if (!ccbFile) ccbFile = @"";
        [NodeGraphPropertySetter setNodeGraphForNode:node andProperty:name withFile:ccbFile parentSize:parentSize];
        [extraProps setObject:ccbFile forKey:name];
    }
    else
    {
        NSLog(@"WARNING Unrecognized property type: %@", type);
    }
}

+ (CCNode*) nodeGraphFromDictionary:(NSDictionary*) dict parentSize:(CGSize)parentSize
{
    if (!renamedProperties)
    {
        renamedProperties = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"CCBReaderInternalRenamedProps" ofType:@"plist"]];
        
        NSAssert(renamedProperties, @"Failed to load renamed properties dict");
        [renamedProperties retain];
    }
    
    NSArray* props = [dict objectForKey:@"properties"];
    NSString* baseClass = [dict objectForKey:@"baseClass"];
    NSArray* children = [dict objectForKey:@"children"];
    
    // Create the node
    CCNode* node = [[PlugInManager sharedManager] createDefaultNodeOfType:baseClass];
    if (!node)
    {
        NSLog(@"WARNING! Plug-in missing for %@", baseClass);
        return NULL;
    }
    
    
    // Fetch info and extra properties
    NodeInfo* nodeInfo = node.userObject;
    NSMutableDictionary* extraProps = nodeInfo.extraProps;
    PlugInNode* plugIn = nodeInfo.plugIn;
    
    // Flash skew compatibility
    if ([[dict objectForKey:@"usesFlashSkew"] boolValue])
    {
        [node setUsesFlashSkew:YES];
    }
    
    // Set properties for the node
    int numProps = [props count];
    for (int i = 0; i < numProps; i++)
    {
        NSDictionary* propInfo = [props objectAtIndex:i];
        NSString* type = [propInfo objectForKey:@"type"];
        NSString* name = [propInfo objectForKey:@"name"];
        id serializedValue = [propInfo objectForKey:@"value"];
        
        // Check for renamings
        NSDictionary* renameRule = [renamedProperties objectForKey:name];
        if (renameRule)
        {
            name = [renameRule objectForKey:@"newName"];
        }
        
        if ([plugIn dontSetInEditorProperty:name])
        {
            [extraProps setObject:serializedValue forKey:name];
        }
        else
        {
            [CCBReaderInternal setProp:name ofType:type toValue:serializedValue forNode:node parentSize:parentSize];
        }
        id baseValue = [propInfo objectForKey:@"baseValue"];
        if (baseValue) [node setBaseValue:baseValue forProperty:name];
    }
    
    // Set extra properties for code connections
    NSString* customClass = [dict objectForKey:@"customClass"];
    if (!customClass) customClass = @"";
    NSString* memberVarName = [dict objectForKey:@"memberVarAssignmentName"];
    if (!memberVarName) memberVarName = @"";
    int memberVarType = [[dict objectForKey:@"memberVarAssignmentType"] intValue];
    
    [extraProps setObject:customClass forKey:@"customClass"];
    [extraProps setObject:memberVarName forKey:@"memberVarAssignmentName"];
    [extraProps setObject:[NSNumber numberWithInt:memberVarType] forKey:@"memberVarAssignmentType"];
    
    // JS code connections
    NSString* jsController = [dict objectForKey:@"jsController"];
    if (jsController)
    {
        [extraProps setObject:jsController forKey:@"jsController"];
    }
    
    NSString* displayName = [dict objectForKey:@"displayName"];
    if (displayName)
    {
        node.displayName = displayName;
    }
    
    id animatedProps = [dict objectForKey:@"animatedProperties"];
    [node loadAnimatedPropertiesFromSerialization:animatedProps];
    node.seqExpanded = [[dict objectForKey:@"seqExpanded"] boolValue];
    
    CGSize contentSize = node.contentSize;
    for (int i = 0; i < [children count]; i++)
    {
        CCNode* child = [CCBReaderInternal nodeGraphFromDictionary:[children objectAtIndex:i] parentSize:contentSize];
        [node addChild:child z:i];
    }
    
    // Physics
    if ([dict objectForKey:@"physicsBody"])
    {
        node.nodePhysicsBody = [[[NodePhysicsBody alloc] initWithSerialization:[dict objectForKey:@"physicsBody"]] autorelease];
    }
    
    // Selections
    if ([[dict objectForKey:@"selected"] boolValue])
    {
        [[AppDelegate appDelegate].loadedSelectedNodes addObject:node];
    }
    
    BOOL isCCBSubFile = [baseClass isEqualToString:@"CCBFile"];
    
    // Load custom properties
    if (isCCBSubFile)
    {
        // For sub ccb files the custom properties are already loaded by the sub file and forwarded. We just need to override the values from the sub ccb file
        [node loadCustomPropertyValuesFromSerialization:[dict objectForKey:@"customProperties"]];
    }
    else
    {
        [node loadCustomPropertiesFromSerialization:[dict objectForKey:@"customProperties"]];
    }
    
    return node;
}

+ (CCNode*) nodeGraphFromDocumentDictionary:(NSDictionary *)dict
{
    return [CCBReaderInternal nodeGraphFromDocumentDictionary:dict parentSize:CGSizeZero];
}

+ (CCNode*) nodeGraphFromDocumentDictionary:(NSDictionary *)dict parentSize:(CGSize) parentSize
{
    if (!dict)
    {
        NSLog(@"WARNING! Trying to load invalid file type (dict is null)");
        return NULL;
    }
    // Load file metadata
    
    NSString* fileType = [dict objectForKey:@"fileType"];
    int fileVersion = [[dict objectForKey:@"fileVersion"] intValue];
    
    if (!fileType  || ![fileType isEqualToString:@"CocosBuilder"])
    {
        NSLog(@"WARNING! Trying to load invalid file type (%@)", fileType);
    }
    
    NSDictionary* nodeGraph = [dict objectForKey:@"nodeGraph"];
    
    if (fileVersion <= 2)
    {
        // Use legacy reader
        NSString* assetsPath = [NSString stringWithFormat:@"%@/", [[ResourceManager sharedManager] mainActiveDirectoryPath]];
        
        return [CCBReaderInternalV1 ccObjectFromDictionary:nodeGraph assetsDir:assetsPath owner:NULL];
    }
    else if (fileVersion > kCCBFileFormatVersion)
    {
        NSLog(@"WARNING! Trying to load file made with a newer version of CocosBuilder");
        return NULL;
    }
    
    return [CCBReaderInternal nodeGraphFromDictionary:nodeGraph parentSize:parentSize];
}

@end
