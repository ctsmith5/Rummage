package services

import (
	"context"

	"google.golang.org/api/option"
	vision "google.golang.org/api/vision/v1"
)

type SafeSearchResult struct {
	Adult    string
	Violence string
	Racy     string
	Spoof    string
	Medical  string
}

// DetectSafeSearch runs Vision SAFE_SEARCH_DETECTION on a GCS URI.
// Ref: https://docs.cloud.google.com/vision/docs/detecting-safe-search#vision_safe_search_detection_gcs-go
func DetectSafeSearch(ctx context.Context, gcsURI string) (*SafeSearchResult, error) {
	// Uses Application Default Credentials in Cloud Run.
	svc, err := vision.NewService(ctx, option.WithScopes(vision.CloudPlatformScope))
	if err != nil {
		return nil, err
	}

	req := &vision.AnnotateImageRequest{
		Image: &vision.Image{
			Source: &vision.ImageSource{GcsImageUri: gcsURI},
		},
		Features: []*vision.Feature{
			{Type: "SAFE_SEARCH_DETECTION"},
		},
	}

	call := svc.Images.Annotate(&vision.BatchAnnotateImagesRequest{
		Requests: []*vision.AnnotateImageRequest{req},
	})
	resp, err := call.Context(ctx).Do()
	if err != nil {
		return nil, err
	}
	if len(resp.Responses) == 0 {
		return &SafeSearchResult{}, nil
	}
	r := resp.Responses[0]
	ss := r.SafeSearchAnnotation
	if ss == nil {
		return &SafeSearchResult{}, nil
	}

	return &SafeSearchResult{
		Adult:    ss.Adult,
		Violence: ss.Violence,
		Racy:     ss.Racy,
		Spoof:    ss.Spoof,
		Medical:  ss.Medical,
	}, nil
}

func isUnsafeLikelyOrHigher(l string) bool {
	return l == "LIKELY" || l == "VERY_LIKELY"
}

func (r *SafeSearchResult) IsUnsafe() bool {
	return isUnsafeLikelyOrHigher(r.Adult) || isUnsafeLikelyOrHigher(r.Violence) || isUnsafeLikelyOrHigher(r.Racy)
}

