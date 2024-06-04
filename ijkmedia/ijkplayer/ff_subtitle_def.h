//
//  ff_subtitle_def.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/5.
//

#ifndef ff_subtitle_def_h
#define ff_subtitle_def_h

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "ijksdl_rectangle.h"

typedef struct FFSubtitleBuffer {
    SDL_Rectangle rect;
    unsigned char *data;
    int refCount;
} FFSubtitleBuffer;

FFSubtitleBuffer * ff_subtitle_buffer_retain(FFSubtitleBuffer *);
void ff_subtitle_buffer_release(FFSubtitleBuffer **);

typedef struct IJKSDLSubtitlePreference {
    float Scale; //字体缩放,默认 1.0
    float BottomMargin;//距离底部距离[0.0, 1.0]
    
    int ForceOverride;//强制使用以下样式
    char FontName[256];//字体名称
    //RGBA,in ass,0 means opaque
    uint32_t PrimaryColour;//主要填充颜色
    uint32_t SecondaryColour;//卡拉OK模式下的预填充
    uint32_t BackColour;//字体阴影色
    uint32_t OutlineColour;//字体边框颜色
    float Outline;//Outline 边框宽度
} IJKSDLSubtitlePreference;

static inline IJKSDLSubtitlePreference ijk_subtitle_default_preference(void)
{
    return (IJKSDLSubtitlePreference){1.0, 0.025, 0, "", 0xFFFFFF00, 0x00FFFF00, 0x00000080, 0, 1};
}

static inline uint32_t str_to_uint32_color(char *token)
{
    char *sep = strrchr(token,'H');
    if (sep) {
        char *color = sep + 1;
        if (color) {
            return (uint32_t)strtol(color, NULL, 16);
        }
    }
    return 0;
}

static inline void uint32_color_to_str(uint32_t color, char *buff, int size)
{
    bzero(buff, size);
    buff[0] = '&';
    buff[1] = 'H';
    
    uint32_t a = color & 0xFF;
    uint32_t r = color >> 8  & 0xFF;
    uint32_t g = color >> 16 & 0xFF;
    uint32_t b = color >> 24 & 0xFF;
    
    sprintf(buff + 2, "%02X", b);
    sprintf(buff + 4, "%02X", g);
    sprintf(buff + 6, "%02X", r);
    sprintf(buff + 8, "%02X", a);
}

static inline int isIJKSDLSubtitlePreferenceEqual(IJKSDLSubtitlePreference* p1,IJKSDLSubtitlePreference* p2)
{
    if (!p1 || !p2) {
        return 0;
    }
    if (p1->ForceOverride != p2->ForceOverride ||
        p1->Scale != p2->Scale ||
        p1->PrimaryColour != p2->PrimaryColour ||
        p1->SecondaryColour != p2->SecondaryColour ||
        p1->BackColour != p2->BackColour ||
        p1->OutlineColour != p2->OutlineColour ||
        p1->Outline != p2->Outline ||
        p1->BottomMargin != p2->BottomMargin ||
        strcmp(p1->FontName, p2->FontName)
        ) {
        return 0;
    }
    return 1;
}

#define SUB_REF_MAX_LEN 6

typedef struct FFSubtitleBufferPacket {
    FFSubtitleBuffer *e[SUB_REF_MAX_LEN];
    int len;
    float scale;
    int bottom_margin;
    int isAss;
    int width;
    int height;
} FFSubtitleBufferPacket;

//return zero means equal
int isFFSubtitleBufferArrayDiff(FFSubtitleBufferPacket *a1, FFSubtitleBufferPacket *a2);
void FreeSubtitleBufferArray(FFSubtitleBufferPacket *a);
void ResetSubtitleBufferArray(FFSubtitleBufferPacket *dst, FFSubtitleBufferPacket *src);

#endif /* ff_subtitle_def_h */
