load("@io_bazel_rules_go//go:def.bzl", "go_library")

go_library(
    name = "go_default_library",
    srcs = ["github.go"],
    importpath = "github.com/adobe/rules_gitops/gitops/git/github",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_google_go_github_v32//github:go_default_library",
        "@org_golang_x_oauth2//:go_default_library",
    ],
)
