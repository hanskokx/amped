# amped_vis

Visualizations for Amped: the classic spectrum analyzer and oscilloscope, the visualization plug-in API, and ports of plug-ins.

## Use

This package is part of the Amped app repository, in `packages/amped_vis`, and the
app depends on it by path:

```yaml
dependencies:
  amped_vis:
    path: packages/amped_vis
```

It depends on other Amped packages:

- [amped_logging](../amped_logging)
- [amped_vis_api](https://git.hadak.org/Amped/amped_vis_api) (its own repository)

## What it provides

- `ClassicAnalyzer`, `ClassicVisRenderer` and `ClassicVisController` draw the
  spectrum analyzer and the oscilloscope of the classic main window
  (`ClassicVisOptions` and `AnalyzerStyle` / `ScopeStyle` choose how).
- The visualization plug-in API (`VisPlugin`, `VisModule`, `VisFrame`,
  `VisContext`) is in [amped_vis_api](https://git.hadak.org/Amped/amped_vis_api)
  and re-exported here. Plug-ins are separate packages, such as
  [tiny_fullscreen_vis](https://git.hadak.org/Amped/tiny_fullscreen_vis).
- `WaveformVis` is a plug-in of one module that draws the waveform as a line,
  so the app has a visualization even when built without a bigger plug-in.
- `VisWorker` runs a plug-in in an isolate of its own and hands back the
  pictures it drew (`VisWorkerFrame`). It is given a top-level function that
  makes the plug-ins (`VisPluginFactory`), as plug-ins can't be sent between
  isolates.

```sh
flutter test
```

## License

This package is covered by the license of the Amped repository it is part of.
