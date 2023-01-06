/*****************************************************************************
 * ijksdl_vout_overlay_ffmpeg.c
 *****************************************************************************
 *
 * Copyright (c) 2013 Bilibili
 * copyright (c) 2013 Zhang Rui <bbcallen@gmail.com>
 *
 * This file is part of ijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * ijkPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with ijkPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include "ijksdl_vout_overlay_ffmpeg.h"
#include "../ijksdl_vout_internal.h"

struct SDL_VoutOverlay_Opaque {
    SDL_mutex *mutex;
    Uint16 pitches[AV_NUM_DATA_POINTERS];

    CVPixelBufferRef pixelBuffer;
    CVPixelBufferPoolRef pixelBufferPool;
};

static SDL_Class g_vout_overlay_ffmpeg_class = {
    .name = "FFmpegVoutOverlay",
};

static NSDictionary* prepareCVPixelBufferAttibutes(const int format,const bool fullRange, const int h, const int w)
{
    //CoreVideo does not provide support for all of these formats; this list just defines their names.
    int pixelFormatType = 0;
    
    if (format == AV_PIX_FMT_RGB24) {
        pixelFormatType = kCVPixelFormatType_24RGB;
    } else if (format == AV_PIX_FMT_ARGB || format == AV_PIX_FMT_0RGB) {
        pixelFormatType = kCVPixelFormatType_32ARGB;
    } else if (format == AV_PIX_FMT_NV12) {
        pixelFormatType = fullRange ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    } else if (format == AV_PIX_FMT_BGRA || format == AV_PIX_FMT_BGR0) {
        pixelFormatType = kCVPixelFormatType_32BGRA;
    } else if (format == AV_PIX_FMT_YUV420P) {
        pixelFormatType = kCVPixelFormatType_420YpCbCr8PlanarFullRange;
    } else if (format == AV_PIX_FMT_YUVJ420P) {
        pixelFormatType = kCVPixelFormatType_420YpCbCr8Planar;
    } else if (format == AV_PIX_FMT_UYVY422) {
        pixelFormatType = kCVPixelFormatType_422YpCbCr8;
    } else if (format == AV_PIX_FMT_YUYV422) {
        pixelFormatType = fullRange ? kCVPixelFormatType_422YpCbCr8FullRange : kCVPixelFormatType_422YpCbCr8_yuvs;
    }
//    Y'0 Cb Y'1 Cr kCVPixelFormatType_422YpCbCr8_yuvs
//    Y'0 Cb Y'1 Cr kCVPixelFormatType_422YpCbCr8FullRange
//    Cb Y'0 Cr Y'1 kCVPixelFormatType_422YpCbCr8
//    ffmpeg only;
//    else if (format == AV_PIX_FMT_YUYV422) {
//        pixelFormatType = kCVPixelFormatType_422YpCbCr8_yuvs;
//    } else if (format == AV_PIX_FMT_YUV444P10) {
//       pixelFormatType = kCVPixelFormatType_444YpCbCr10;
//    } else if (format == AV_PIX_FMT_NV16) {
//       pixelFormatType = fullRange ? kCVPixelFormatType_422YpCbCr8BiPlanarFullRange : kCVPixelFormatType_422YpCbCr8BiPlanarVideoRange;
//    }
    //    kCVReturnInvalidPixelFormat
//    else if (format == AV_PIX_FMT_BGR24) {
//        pixelFormatType = kCVPixelFormatType_24BGR;
//    }
//    else if (format == AV_PIX_FMT_RGB565BE) {
//        pixelFormatType = kCVPixelFormatType_16BE565;
//    } else if (format == AV_PIX_FMT_RGB565LE) {
//        pixelFormatType = kCVPixelFormatType_16LE565;
//    }
//    else if (format == AV_PIX_FMT_RGB0 || format == AV_PIX_FMT_RGBA) {
//        pixelFormatType = kCVPixelFormatType_32RGBA;
//    }
//    RGB555 可以创建出 CVPixelBuffer，但是显示时失败了。
//    else if (format == AV_PIX_FMT_RGB555BE) {
//        pixelFormatType = kCVPixelFormatType_16BE555;
//    } else if (format == AV_PIX_FMT_RGB555LE) {
//        pixelFormatType = kCVPixelFormatType_16LE555;
//    }
    else {
        ALOGE("unsupported pixel format:%d!",format);
        assert(false);
        return nil;
    }
    
    const int linesize = 32;//FFmpeg 解码数据对齐是32，这里期望CVPixelBuffer也能使用32对齐，但实际来看却是64！
    NSMutableDictionary*attributes = [NSMutableDictionary dictionary];
    [attributes setObject:@(pixelFormatType) forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
    [attributes setObject:[NSNumber numberWithInt:w] forKey:(NSString*)kCVPixelBufferWidthKey];
    [attributes setObject:[NSNumber numberWithInt:h] forKey:(NSString*)kCVPixelBufferHeightKey];
    [attributes setObject:@(linesize) forKey:(NSString*)kCVPixelBufferBytesPerRowAlignmentKey];
    [attributes setObject:[NSDictionary dictionary] forKey:(NSString*)kCVPixelBufferIOSurfacePropertiesKey];
    return attributes;
}

static CVReturn createCVPixelBufferPoolFromAVFrame(CVPixelBufferPoolRef * poolRef, int width, int height, int format)
{
    if (NULL == poolRef) {
        return kCVReturnInvalidArgument;
    }
    
    CVReturn result = kCVReturnError;
    //FIXME TODO
    const bool fullRange = true;
    NSDictionary * attributes = prepareCVPixelBufferAttibutes(format, fullRange, height, width);
    
    result = CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef) attributes, poolRef);
    
    if (result != kCVReturnSuccess) {
        ALOGE("CVPixelBufferCreate Failed:%d\n", result);
    }
    return result;
}

static CVPixelBufferRef createCVPixelBufferFromAVFrame(const AVFrame *frame,CVPixelBufferPoolRef poolRef)
{
    if (NULL == frame) {
        return NULL;
    }
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn result = kCVReturnError;
    
    const int w = frame->width;
    const int h = frame->height;
    const int format = frame->format;
    
    assert(w);
    assert(h);
    
    if (poolRef) {
        result = CVPixelBufferPoolCreatePixelBuffer(NULL, poolRef, &pixelBuffer);
    }
    
    if (kCVReturnSuccess != result) {
        ALOGE("CVPixelBufferPoolCreatePixelBuffer Failed:%d\n", result);
        //AVCOL_RANGE_MPEG对应tv，AVCOL_RANGE_JPEG对应pc
        //Y′ values are conventionally shifted and scaled to the range [16, 235] (referred to as studio swing or "TV levels") rather than using the full range of [0, 255] (referred to as full swing or "PC levels").
        //https://en.wikipedia.org/wiki/YUV#Numerical_approximations
        
        const bool fullRange = frame->color_range != AVCOL_RANGE_MPEG;
        NSDictionary * attributes = prepareCVPixelBufferAttibutes(format, fullRange, h, w);
        
        if (!attributes) {
            ALOGE("CVPixelBufferCreate Failed: no attributes\n");
            assert(0);
            return NULL;
        }
        const int pixelFormatType = [attributes[(NSString*)kCVPixelBufferPixelFormatTypeKey] intValue];
        
        result = CVPixelBufferCreate(kCFAllocatorDefault,
                                     w,
                                     h,
                                     pixelFormatType,
                                     (__bridge CFDictionaryRef)(attributes),
                                     &pixelBuffer);
    }
    
    if (kCVReturnSuccess == result) {
        
        int planes = 1;
        if (CVPixelBufferIsPlanar(pixelBuffer)) {
            planes = (int)CVPixelBufferGetPlaneCount(pixelBuffer);
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer,0);
        for (int p = 0; p < planes; p++) {
            uint8_t *src = frame->data[p];
            uint8_t *dst = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, p);
            if (!src || !dst) {
                continue;
            }
            
            int src_linesize = (int)frame->linesize[p];
            int dst_linesize = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, p);
            int height = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, p);
            
            if (src_linesize == dst_linesize) {
                memcpy(dst, src, dst_linesize * height);
            } else {
                int bytewidth = MIN(src_linesize, dst_linesize);
                av_image_copy_plane(dst, dst_linesize, src, src_linesize, bytewidth, height);
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        return pixelBuffer;
    } else {
        ALOGE("CVPixelBufferCreate Failed:%d\n", result);
        assert(0);
        return NULL;
    }
}

static bool check_object(SDL_VoutOverlay* object, const char *func_name)
{
    if (!object || !object->opaque || !object->opaque_class) {
        ALOGE("%s: invalid pipeline\n", func_name);
        return false;
    }

    if (object->opaque_class != &g_vout_overlay_ffmpeg_class) {
        ALOGE("%s.%s: unsupported method\n", object->opaque_class->name, func_name);
        return false;
    }

    return true;
}

CVPixelBufferRef SDL_VoutFFmpeg_GetCVPixelBufferRef(SDL_VoutOverlay *overlay)
{
    if (!check_object(overlay, __func__))
        return NULL;

    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    return opaque->pixelBuffer;
}

static void func_free_l(SDL_VoutOverlay *overlay)
{
    ALOGE("SDL_Overlay(ffmpeg): overlay_free_l(%p)\n", overlay);
    if (!overlay)
        return;

    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    if (!opaque)
        return;

    if (opaque->pixelBuffer) {
        CVPixelBufferRelease(opaque->pixelBuffer);
        opaque->pixelBuffer = NULL;
    }
    
    if (opaque->mutex)
        SDL_DestroyMutex(opaque->mutex);
    
    SDL_VoutOverlay_FreeInternal(overlay);
}

static int func_lock(SDL_VoutOverlay *overlay)
{
    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    return SDL_LockMutex(opaque->mutex);
}

static int func_unlock(SDL_VoutOverlay *overlay)
{
    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    return SDL_UnlockMutex(opaque->mutex);
}

static int func_fill_avframe_to_cvpixelbuffer(SDL_VoutOverlay *overlay, const AVFrame *frame)
{
    assert(overlay);
    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    
    if (opaque->pixelBuffer) {
        CVPixelBufferRelease(opaque->pixelBuffer);
        opaque->pixelBuffer = NULL;
    }
    
    CVPixelBufferPoolRef poolRef = NULL;
    if (opaque->pixelBufferPool) {
        NSDictionary *attributes = (__bridge NSDictionary *)CVPixelBufferPoolGetPixelBufferAttributes(opaque->pixelBufferPool);
        int _width = [[attributes objectForKey:(NSString*)kCVPixelBufferWidthKey] intValue];
        int _height = [[attributes objectForKey:(NSString*)kCVPixelBufferHeightKey] intValue];
        if (frame->width == _width && frame->height == _height) {
            poolRef = opaque->pixelBufferPool;
        }
    }
    CVPixelBufferRef pixel_buffer = createCVPixelBufferFromAVFrame(frame, poolRef);
    if (pixel_buffer) {
        opaque->pixelBuffer = pixel_buffer;
        
        if (CVPixelBufferIsPlanar(pixel_buffer)) {
            int planes = (int)CVPixelBufferGetPlaneCount(pixel_buffer);
            for (int i = 0; i < planes; i ++) {
                overlay->pitches[i] = CVPixelBufferGetWidthOfPlane(pixel_buffer, i);
            }
        } else {
            overlay->pitches[0] = CVPixelBufferGetWidth(pixel_buffer);
        }
        return 0;
    }
    return 1;
}

struct SDL_Vout_Opaque {
    void *cvPixelBufferPool;
    int cv_format;
};

#ifndef __clang_analyzer__
SDL_VoutOverlay *SDL_VoutFFmpeg_CreateOverlay(int width, int height,int src_format, int cvpixelbufferpool, SDL_Vout *display)
{
    Uint32 overlay_format = display->overlay_format;
    
    SDL_VoutOverlay *overlay = SDL_VoutOverlay_CreateInternal(sizeof(SDL_VoutOverlay_Opaque));
    if (!overlay) {
        ALOGE("overlay allocation failed");
        return NULL;
    }

    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    opaque->mutex         = SDL_CreateMutex();
    overlay->opaque_class = &g_vout_overlay_ffmpeg_class;
    overlay->format       = SDL_FCC__FFVTB;
    overlay->is_private   = 1;
    overlay->pitches      = opaque->pitches;
    overlay->w            = width;
    overlay->h            = height;
    overlay->free_l             = func_free_l;
    overlay->lock               = func_lock;
    overlay->unlock             = func_unlock;
    overlay->func_fill_frame    = func_fill_avframe_to_cvpixelbuffer;
    
    enum AVPixelFormat const format = src_format;
    assert(format != AV_PIX_FMT_NONE);

    SDLTRACE("SDL_VoutFFmpeg_CreateOverlay(w=%d, h=%d, fmt=%.4s, dp=%p)\n",
             width, height, (const char*) &overlay_format, display);
    
    SDL_Vout_Opaque * voutOpaque = display->opaque;
    if (cvpixelbufferpool && !voutOpaque->cvPixelBufferPool) {
        CVPixelBufferPoolRef cvPixelBufferPool = NULL;
        createCVPixelBufferPoolFromAVFrame(&cvPixelBufferPool, width, height, format);
        voutOpaque->cvPixelBufferPool = cvPixelBufferPool;
        voutOpaque->cv_format = format;
    }
    
    if (voutOpaque->cv_format == format) {
        opaque->pixelBufferPool = (CVPixelBufferPoolRef)voutOpaque->cvPixelBufferPool;
    }

    return overlay;
}
#endif//__clang_analyzer__
