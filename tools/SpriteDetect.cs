using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Text;

public static class SpriteDetect
{
	public static void Run(string inputPath, string outJson, string outContact)
	{
		using (var bmp = new Bitmap(inputPath))
		{
			int w = bmp.Width, h = bmp.Height;
			var px = new int[w * h];
			var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
			System.Runtime.InteropServices.Marshal.Copy(data.Scan0, px, 0, px.Length);
			bmp.UnlockBits(data);

			int bg = px[0];
			Func<int, bool> isFg = (p) =>
			{
				int a = (p >> 24) & 0xFF;
				if (a < 16) return false;
				// tolerance match against bg
				int dr = Math.Abs(((p >> 16) & 0xFF) - ((bg >> 16) & 0xFF));
				int dg = Math.Abs(((p >> 8) & 0xFF) - ((bg >> 8) & 0xFF));
				int db = Math.Abs((p & 0xFF) - (bg & 0xFF));
				return (dr + dg + db) > 24;
			};

			// connected components with reach-2 neighborhood (merges close parts)
			var label = new int[w * h];
			for (int i = 0; i < label.Length; i++) label[i] = -1;
			var boxes = new List<int[]>(); // x0,y0,x1,y1
			int reach = 3;
			var stack = new Stack<int>();
			int next = 0;
			for (int y = 0; y < h; y++)
			for (int x = 0; x < w; x++)
			{
				int idx = y * w + x;
				if (label[idx] != -1 || !isFg(px[idx])) continue;
				int x0 = x, y0 = y, x1 = x, y1 = y;
				label[idx] = next;
				stack.Push(idx);
				while (stack.Count > 0)
				{
					int c = stack.Pop();
					int cy = c / w, cx = c % w;
					if (cx < x0) x0 = cx; if (cx > x1) x1 = cx;
					if (cy < y0) y0 = cy; if (cy > y1) y1 = cy;
					for (int dy = -reach; dy <= reach; dy++)
					for (int dx = -reach; dx <= reach; dx++)
					{
						int nx = cx + dx, ny = cy + dy;
						if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
						int ni = ny * w + nx;
						if (label[ni] == -1 && isFg(px[ni]))
						{
							label[ni] = next;
							stack.Push(ni);
						}
					}
				}
				boxes.Add(new[] { x0, y0, x1, y1 });
				next++;
			}

			// filter specks
			boxes = boxes.Where(b => (b[2] - b[0] + 1) * (b[3] - b[1] + 1) >= 16).ToList();
			// sort into rows: group by vertical overlap
			boxes.Sort((a, b) => a[1] != b[1] ? a[1] - b[1] : a[0] - b[0]);
			var rows = new List<List<int[]>>();
			foreach (var b in boxes)
			{
				bool placed = false;
				foreach (var r in rows)
				{
					// overlap with row's y-range
					int ry0 = r.Min(q => q[1]), ry1 = r.Max(q => q[3]);
					int ov = Math.Min(ry1, b[3]) - Math.Max(ry0, b[1]);
					if (ov > 0.3 * (b[3] - b[1])) { r.Add(b); placed = true; break; }
				}
				if (!placed) rows.Add(new List<int[]> { b });
			}
			foreach (var r in rows) r.Sort((a, b) => a[0] - b[0]);
			rows.Sort((a, b) => a.Min(q => q[1]) - b.Min(q => q[1]));

			var sb = new StringBuilder();
			sb.Append("[\n");
			int gi = 0;
			var flat = new List<int[]>();
			for (int ri = 0; ri < rows.Count; ri++)
			{
				foreach (var b in rows[ri])
				{
					sb.AppendFormat("  {{\"i\":{0},\"row\":{1},\"x\":{2},\"y\":{3},\"w\":{4},\"h\":{5}}},\n",
						gi, ri, b[0], b[1], b[2] - b[0] + 1, b[3] - b[1] + 1);
					flat.Add(b);
					gi++;
				}
			}
			if (sb.Length > 2) sb.Length -= 2;
			sb.Append("\n]\n");
			File.WriteAllText(outJson, sb.ToString());

			// contact sheet: scale 2x, draw boxes + indices
			int scale = 2;
			using (var sheet = new Bitmap(w * scale, h * scale))
			using (var g = Graphics.FromImage(sheet))
			{
				g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
				g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
				using (var src = new Bitmap(inputPath))
					g.DrawImage(src, new Rectangle(0, 0, w * scale, h * scale));
				using (var pen = new Pen(Color.Red, 1))
				using (var font = new Font("Arial", 9, FontStyle.Bold))
				using (var brush = new SolidBrush(Color.Yellow))
				using (var back = new SolidBrush(Color.FromArgb(180, 0, 0, 0)))
				{
					for (int i = 0; i < flat.Count; i++)
					{
						var b = flat[i];
						g.DrawRectangle(pen, b[0] * scale, b[1] * scale, (b[2] - b[0] + 1) * scale, (b[3] - b[1] + 1) * scale);
						string t = i.ToString();
						var sz = g.MeasureString(t, font);
						g.FillRectangle(back, b[0] * scale, b[1] * scale - sz.Height, sz.Width, sz.Height);
						g.DrawString(t, font, brush, b[0] * scale, b[1] * scale - sz.Height);
					}
				}
				sheet.Save(outContact, ImageFormat.Png);
			}
			Console.WriteLine("components=" + flat.Count + " rows=" + rows.Count + " bg=" + bg.ToString("X8"));
		}
	}
}
