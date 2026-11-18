using System;
using Cognex.VisionPro;
using Cognex.VisionPro.ToolGroup;
using Cognex.VisionPro.PMAlign;
using Cognex.VisionPro.Blob;

// QuickBuild still performs the image processing. This script orders the tools,
// checks empty/low-score matches before using their poses, and records a reason.
public class UserScript : CogToolGroupBaseScript
{
  private void Put(string name, object value)
  {
    toolGroup.SetScriptTerminalData(name, value);
  }

  private double Setting(string name)
  {
    return Convert.ToDouble(toolGroup.GetScriptTerminalData(name));
  }

  private bool RunChecked(string name, ref string message,
                          ref CogToolResultConstants result)
  {
    ICogTool tool = toolGroup.Tools[name];
    toolGroup.RunTool(tool, ref message, ref result);
    if (tool.RunStatus.Result == CogToolResultConstants.Error ||
        tool.RunStatus.Result == CogToolResultConstants.Reject)
      return false;
    return true;
  }

  private bool Finish(string reason, bool ok, ref string message,
                      ref CogToolResultConstants result)
  {
    Put("FinalOK", ok);
    Put("Decision", ok ? "OK" : "NG");
    Put("Reason", reason);
    message = reason;
    result = ok ? CogToolResultConstants.Accept : CogToolResultConstants.Reject;
    return false;
  }

  public override bool GroupRun(ref string message, ref CogToolResultConstants result)
  {
    // Reset every frame so a failed frame cannot publish the previous pose.
    Put("FinalOK", false);
    Put("Decision", "NG");
    Put("Reason", "NOT_EVALUATED");
    Put("ErrorDetail", "");
    Put("BoardFound", false);
    Put("TargetFound", false);
    Put("BoardScore", 0.0);
    Put("TargetScore", 0.0);
    Put("TargetX", Double.NaN);
    Put("TargetY", Double.NaN);
    Put("DeltaX", Double.NaN);
    Put("DeltaY", Double.NaN);
    Put("BlobCount", 0);
    result = CogToolResultConstants.Accept;
    message = "";

    try
    {
      if (!RunChecked("Image Source", ref message, ref result) ||
          !RunChecked("CogImageConvertTool1", ref message, ref result))
        return Finish("IMAGE_TOOL_ERROR", false, ref message, ref result);

      if (!RunChecked("CogPMAlignTool1", ref message, ref result))
        return Finish("BOARD_TOOL_ERROR", false, ref message, ref result);

      CogPMAlignTool board = (CogPMAlignTool)toolGroup.Tools["CogPMAlignTool1"];
      if (board.Results == null || board.Results.Count == 0)
        return Finish("BOARD_NOT_FOUND", false, ref message, ref result);
      CogPMAlignResult boardMatch = board.Results[0];
      Put("BoardScore", boardMatch.Score);
      if (!boardMatch.Accepted)
        return Finish("BOARD_LOW_SCORE", false, ref message, ref result);
      Put("BoardFound", true);

      // The Fixture's original GetPose binding is reached only after this check.
      if (!RunChecked("CogFixtureTool1", ref message, ref result))
        return Finish("FIXTURE_TOOL_ERROR", false, ref message, ref result);
      if (!RunChecked("CogPMAlignTool2", ref message, ref result))
        return Finish("TARGET_TOOL_ERROR", false, ref message, ref result);
      if (!RunChecked("CogBlobTool1", ref message, ref result))
        return Finish("BLOB_TOOL_ERROR", false, ref message, ref result);

      CogBlobTool blob = (CogBlobTool)toolGroup.Tools["CogBlobTool1"];
      int count = blob.Results.GetBlobs().Count;
      Put("BlobCount", count);

      // Keep the original QuickBuild Results Analysis tool visible and active.
      toolGroup.RunTool(toolGroup.Tools["CogResultsAnalysisTool1"], ref message, ref result);
      if (toolGroup.Tools["CogResultsAnalysisTool1"].RunStatus.Result == CogToolResultConstants.Error)
        return Finish("ANALYSIS_TOOL_ERROR", false, ref message, ref result);

      CogPMAlignTool target = (CogPMAlignTool)toolGroup.Tools["CogPMAlignTool2"];
      if (target.Results == null || target.Results.Count == 0)
        return Finish(count == 0 ? "TARGET_MISSING" : "TARGET_NOT_FOUND",
                      false, ref message, ref result);
      CogPMAlignResult targetMatch = target.Results[0];
      Put("TargetScore", targetMatch.Score);
      if (!targetMatch.Accepted)
        return Finish("TARGET_LOW_SCORE", false, ref message, ref result);

      CogTransform2DLinear pose = targetMatch.GetPose();
      double dx = pose.TranslationX - Setting("ReferenceX");
      double dy = pose.TranslationY - Setting("ReferenceY");
      Put("TargetFound", true);
      Put("TargetX", pose.TranslationX);
      Put("TargetY", pose.TranslationY);
      Put("DeltaX", dx);
      Put("DeltaY", dy);
      if (Double.IsNaN(dx) || Double.IsInfinity(dx) ||
          Double.IsNaN(dy) || Double.IsInfinity(dy))
        return Finish("INVALID_POSE", false, ref message, ref result);

      double tx = Setting("ToleranceX");
      double ty = Setting("ToleranceY");
      if (Double.IsNaN(tx) || Double.IsInfinity(tx) || tx <= 0 ||
          Double.IsNaN(ty) || Double.IsInfinity(ty) || ty <= 0)
        return Finish("INVALID_TOLERANCE", false, ref message, ref result);

      // Position is judged before fixed-ROI text, since a moved resistor can
      // leave the text ROI even when PMAlign still locates it nearby.
      if (Math.Abs(dx) > tx || Math.Abs(dy) > ty)
        return Finish("TARGET_OUT_OF_POSITION", false, ref message, ref result);
      if (count < 1)
        return Finish("TARGET_TEXT_NOT_FOUND", false, ref message, ref result);
      return Finish("PASS", true, ref message, ref result);
    }
    catch (Exception ex)
    {
      Put("ErrorDetail", ex.GetType().Name + ": " + ex.Message);
      return Finish("TOOL_EXCEPTION", false, ref message, ref result);
    }
  }

  public override void Initialize(CogToolGroup host)
  {
    base.Initialize(host);
    // Cognex requires script terminals to be declared on every initialization,
    // including when QuickBuild reloads a saved application.
    toolGroup.DefineScriptTerminal(215.99061998603671, "ReferenceX", true);
    toolGroup.DefineScriptTerminal(455.9832554235843, "ReferenceY", true);
    toolGroup.DefineScriptTerminal(20.0, "ToleranceX", true);
    toolGroup.DefineScriptTerminal(8.0, "ToleranceY", true);
    toolGroup.DefineScriptTerminal(false, "FinalOK", false);
    toolGroup.DefineScriptTerminal("NG", "Decision", false);
    toolGroup.DefineScriptTerminal("NOT_EVALUATED", "Reason", false);
    toolGroup.DefineScriptTerminal("", "ErrorDetail", false);
    toolGroup.DefineScriptTerminal(false, "BoardFound", false);
    toolGroup.DefineScriptTerminal(false, "TargetFound", false);
    toolGroup.DefineScriptTerminal(0.0, "BoardScore", false);
    toolGroup.DefineScriptTerminal(0.0, "TargetScore", false);
    toolGroup.DefineScriptTerminal(Double.NaN, "TargetX", false);
    toolGroup.DefineScriptTerminal(Double.NaN, "TargetY", false);
    toolGroup.DefineScriptTerminal(Double.NaN, "DeltaX", false);
    toolGroup.DefineScriptTerminal(Double.NaN, "DeltaY", false);
    toolGroup.DefineScriptTerminal(0, "BlobCount", false);
  }
}
