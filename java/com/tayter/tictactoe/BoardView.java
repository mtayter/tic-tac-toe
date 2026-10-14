package com.tayter.tictactoe;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.View;

/**
 * Two-player tic-tac-toe board. Player 1 is a red X, player 2 is a blue O.
 * No AI, no settings. A win draws a line through the winning cells in the
 * winner's color; a draw draws nothing.
 */
public class BoardView extends View {

    private static final int EMPTY = 0;
    private static final int X = 1; // player 1, red
    private static final int O = 2; // player 2, blue

    private static final int[][] LINES = {
            {0, 1, 2}, {3, 4, 5}, {6, 7, 8}, // rows
            {0, 3, 6}, {1, 4, 7}, {2, 5, 8}, // columns
            {0, 4, 8}, {2, 4, 6}             // diagonals
    };

    private static final int RED = 0xFFF44336;
    private static final int BLUE = 0xFF2196F3;
    private static final int GRID = 0xFFBDBDBD;

    private final int[] cells = new int[9];
    private int turn = X; // X always moves first
    private boolean gameOver = false;
    private int[] winLine = null; // winning cell indices, null until someone wins

    private final Paint gridPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint xPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint oPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint winPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    public BoardView(Context context, AttributeSet attrs) {
        super(context, attrs);

        gridPaint.setColor(GRID);
        gridPaint.setStyle(Paint.Style.STROKE);

        xPaint.setColor(RED);
        xPaint.setStyle(Paint.Style.STROKE);
        xPaint.setStrokeCap(Paint.Cap.ROUND);

        oPaint.setColor(BLUE);
        oPaint.setStyle(Paint.Style.STROKE);
        oPaint.setStrokeCap(Paint.Cap.ROUND);

        winPaint.setStyle(Paint.Style.STROKE);
        winPaint.setStrokeCap(Paint.Cap.ROUND);
    }

    public void newGame() {
        for (int i = 0; i < 9; i++) {
            cells[i] = EMPTY;
        }
        turn = X;
        gameOver = false;
        winLine = null;
        invalidate();
    }

    // Board geometry, recomputed each draw from the view's actual size.
    private float boardLeft, boardTop, cell;

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);

        float size = Math.min(getWidth(), getHeight());
        boardLeft = (getWidth() - size) / 2f;
        boardTop = (getHeight() - size) / 2f;
        cell = size / 3f;

        float markStroke = size * 0.045f;
        gridPaint.setStrokeWidth(size * 0.012f);
        xPaint.setStrokeWidth(markStroke);
        oPaint.setStrokeWidth(markStroke);
        winPaint.setStrokeWidth(size * 0.055f);

        // Grid: two vertical, two horizontal lines.
        for (int i = 1; i <= 2; i++) {
            float p = boardLeft + i * cell;
            canvas.drawLine(p, boardTop, p, boardTop + size, gridPaint);
            float q = boardTop + i * cell;
            canvas.drawLine(boardLeft, q, boardLeft + size, q, gridPaint);
        }

        // Marks.
        for (int i = 0; i < 9; i++) {
            if (cells[i] == X) {
                drawX(canvas, i);
            } else if (cells[i] == O) {
                drawO(canvas, i);
            }
        }

        // Win line through the winner's cells, in the winner's color.
        if (winLine != null) {
            winPaint.setColor(cells[winLine[0]] == X ? RED : BLUE);
            float x0 = cellCenterX(winLine[0]);
            float y0 = cellCenterY(winLine[0]);
            float x1 = cellCenterX(winLine[2]);
            float y1 = cellCenterY(winLine[2]);
            // Extend a touch past the outer cells' centers so the line
            // spans the marks.
            float dx = x1 - x0;
            float dy = y1 - y0;
            float len = (float) Math.hypot(dx, dy);
            if (len > 0) {
                float ext = cell * 0.3f;
                dx /= len;
                dy /= len;
                x0 -= dx * ext;
                y0 -= dy * ext;
                x1 += dx * ext;
                y1 += dy * ext;
            }
            canvas.drawLine(x0, y0, x1, y1, winPaint);
        }
        // Draw: nothing drawn. Exactly as specified.
    }

    private float cellCenterX(int i) {
        return boardLeft + (i % 3) * cell + cell / 2f;
    }

    private float cellCenterY(int i) {
        return boardTop + (i / 3) * cell + cell / 2f;
    }

    private void drawX(Canvas canvas, int i) {
        float cx = cellCenterX(i);
        float cy = cellCenterY(i);
        float r = cell * 0.30f;
        canvas.drawLine(cx - r, cy - r, cx + r, cy + r, xPaint);
        canvas.drawLine(cx + r, cy - r, cx - r, cy + r, xPaint);
    }

    private void drawO(Canvas canvas, int i) {
        canvas.drawCircle(cellCenterX(i), cellCenterY(i), cell * 0.32f, oPaint);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (event.getAction() != MotionEvent.ACTION_DOWN || gameOver) {
            return true;
        }
        float x = event.getX();
        float y = event.getY();
        int col = (int) ((x - boardLeft) / cell);
        int row = (int) ((y - boardTop) / cell);
        if (col < 0 || col > 2 || row < 0 || row > 2) {
            return true;
        }
        int i = row * 3 + col;
        if (cells[i] != EMPTY) {
            return true;
        }
        cells[i] = turn;
        checkGameOver();
        if (!gameOver) {
            turn = (turn == X) ? O : X;
        }
        invalidate();
        return true;
    }

    private void checkGameOver() {
        for (int[] line : LINES) {
            int a = cells[line[0]];
            if (a != EMPTY && a == cells[line[1]] && a == cells[line[2]]) {
                gameOver = true;
                winLine = line;
                return;
            }
        }
        boolean full = true;
        for (int c : cells) {
            if (c == EMPTY) {
                full = false;
                break;
            }
        }
        if (full) {
            gameOver = true; // draw: winLine stays null, nothing extra drawn
        }
    }
}
